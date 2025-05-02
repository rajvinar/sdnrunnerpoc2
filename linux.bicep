param location string = resourceGroup().location


param vmsssku string = 'Standard_D8s_v3'
param vmsscount int = 1
param resourceGroupName string = resourceGroup().name

param name string
param adminUsername string = 'azureuser'
@secure()
param adminPassword string

param subscriptionId string = subscription().subscriptionId

param vnetname string
param vnetrgname string
param subnetname string = 'nodes'
param extensionName string
param aksClusterKubeletIdentityId string

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'TrustedLaunch'

resource aksbootstrapid 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  scope: resourceGroup(subscriptionId, resourceGroupName) 
  name: 'helm-script-msi3'
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-09-01' existing = {
  scope: resourceGroup(subscriptionId, vnetrgname) 
  name: vnetname
}



var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}


var delegatenics = [
  for idx in range(0, 3): {
    name: 'delegate-nic${idx}'
    properties: {
      enableAcceleratedNetworking: true
      ipConfigurations: [
        {
          name: 'delegate-ip${idx}'
          properties: {
            subnet: {
              id: '${vnet.id}/subnets/${subnetname}'
            }
          }
        }
      ]
    }
  }
]

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  location: location
  name: name
  tags: {
    AzSecPackAutoConfigReady: 'true'
    'delegate-ip-allocation-for-nics-without-subnet': 'true'
    'aks-nic-enable-multi-tenancy': 'true'
    'delegate-ip-allocation-nic-prefix': 'delegate'
    fastpathenabled: 'true'
	  Skip1PGalleryEnforcement: 'true'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksbootstrapid.id}': {}
      '${aksClusterKubeletIdentityId}': {}
    }
  }
  sku: {
    name: vmsssku
    tier: 'Standard'
    capacity: vmsscount
  }
  properties: {
    orchestrationMode: 'Uniform'
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
      automaticOSUpgradePolicy: {
        enableAutomaticOSUpgrade: true
      }
    }

    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: 'canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          diskSizeGB: 500
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      }
      extensionProfile: {
        extensions: [
          {
            name: '${extensionName}'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                script: vmextscript.outputs.scripts[vmsssku]
              }
            }
          }
          {
            name: 'HealthExtension'             
            properties: {               
              publisher: 'Microsoft.ManagedServices'               
              type: 'ApplicationHealthLinux'               
              typeHandlerVersion: '1.0'               
              autoUpgradeMinorVersion: true               
              settings: {                 
                port: 80                 
                protocol: 'http'                 
                requestPath: '/health'               
              }             
            }        
          }
        ]
      }
      osProfile: {
        computerNamePrefix: name
        adminUsername: adminUsername
        adminPassword: adminPassword
        linuxConfiguration: {
          disablePasswordAuthentication: false
        }
      }
	  securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
      networkProfile: {
        networkInterfaceConfigurations: concat(
          [
            {
              name: 'primary-nic'
              properties: {
                primary: true
                enableAcceleratedNetworking: true
                ipConfigurations: [
                  {
                    name: 'primary-ip'
                    properties: {
                      subnet: {
                        id: '${vnet.id}/subnets/${subnetname}'
                      }
                      primary: true
                      publicIPAddressConfiguration: {
                        name: 'pub'
                        sku: {
                          name: 'Standard'
                        }
                      }
                    }
                  }
                ]
              }
            }
          ],
          delegatenics 
        )
      }
    }
  }
}
module vmextscript 'provisionscript.bicep' = {
  name: extensionName
  params: {
    extversion: '000000'
    hubgroup: resourceGroupName
    hubsub: subscriptionId
  }
}
