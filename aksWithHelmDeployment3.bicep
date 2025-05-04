@description('Name of the cluster')
param clusterName string
@description('Region')
param region string
@description('Resource Group')
param rg string
@description('Name of the cosmosdb')
param cosmosdbName string

@description('Subscription ID')
param subscriptionId string
param infraVnetName string = 'infraVnet'
param infraSubnetName string = 'infraSubnet'
param aciSubnetName string = 'aci-subnet'
param customerVnetName string = 'customerVnet'
param delegatedSubnetName string = 'delegatedSubnet'
param delegatedSubnet1Name string = 'delegatedSubnet1'
param dncVMSSNames array = ['dncpool20']
param workerVMSSNames array = ['linuxpool20', 'linuxpool21']




// TODO: will be different in ame need to check pr
param subnetDelegatorEnvironment string = 'env-westus-u3h4j'
param subnetDelegatorName string = 'subnetdelegator-westus-u3h4j'
param subnetDelegatorRg string = 'subnetdelegator-westus'
// param subnetDelegatorSubscriptionId string = 'b2f3c0a1-4d5e-4b8e-9f7c-6d5a0f1b2c3d'
param subnetDelegatorSubscriptionId string = '9b8218f9-902a-4d20-a65c-e98acec5362f'
////////////////
param msiRg string = 'RunnersIdentities'





var dataActions = [
  'Microsoft.DocumentDB/databaseAccounts/readMetadata'
  'Microsoft.DocumentDB/databaseAccounts/throughputSettings/*'
  'Microsoft.DocumentDB/databaseAccounts/tables/write'
  'Microsoft.DocumentDB/databaseAccounts/tables/containers/write'
  'Microsoft.DocumentDB/databaseAccounts/tables/containers/executeQuery'
  'Microsoft.DocumentDB/databaseAccounts/tables/containers/executeStoredProcedure'
  'Microsoft.DocumentDB/databaseAccounts/tables/containers/entities/*'
] 


resource customRole 'Microsoft.DocumentDB/databaseAccounts/tableRoleDefinitions@2024-12-01-preview' = {
  name: guid(cosmosdb.id, 'DncCosmosDbRbacRole')
  parent: cosmosdb
  properties: {
    roleName: 'DncCosmosDbRbacRole'
    type: 'CustomRole'
    permissions: [
      {
        dataActions: dataActions
      }
    ]
    assignableScopes: [
      '${cosmosdb.id}'
    ]
  }
}

resource aksClusterKubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'aksClusterKubeletIdentity'
  location: region
}

resource cosmosdbRoleAssignmentForDNC 'Microsoft.DocumentDB/databaseAccounts/tableRoleAssignments@2024-12-01-preview' = {
  name: guid(cosmosdb.id, customRole.id, 'aksClusterKubeletIdentity', 'roleAssignment')
  parent: cosmosdb
  properties: {
    principalId: aksClusterKubeletIdentity.properties.principalId
    roleDefinitionId: customRole.id
    scope: cosmosdb.id
  }
}

module roleAssignments './roleAssignmentsInSub.bicep' = {
  name: 'roleAssignmentsDeployment'
  scope: subscription() // Explicitly set the module scope to subscription
  params: {
    principalId: aksClusterKubeletIdentity.properties.principalId
  }
}



resource subnetDelegator 'Microsoft.App/containerApps@2024-10-02-preview' existing = {
  name: subnetDelegatorName
  scope: resourceGroup(subnetDelegatorSubscriptionId, subnetDelegatorRg)
}

resource subnetDelegatorAcaEnv 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: subnetDelegatorEnvironment
  scope: resourceGroup(subnetDelegatorSubscriptionId, subnetDelegatorRg)
}

resource ip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'aciNatGw-ip-${uniqueString(resourceGroup().name)}'
  location: region
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    ipTags: [
      {
        ipTagType: 'FirstPartyUsage'
        tag: '/DelegatedNetworkControllerTest'
      }
    ]
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource aciNatGw 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'aciNatGw-${uniqueString(resourceGroup().name)}'
  location: region
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses:[ {
      id: ip.id
    }]
  }
}

resource outboundIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'serviceTaggedIp-${clusterName}'
  location: region
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    ipTags: [
      {
        ipTagType: 'FirstPartyUsage'
        tag: '/DelegatedNetworkControllerTest'
      }
    ]
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}
resource infraVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: infraVnetName
  location: region
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.224.0.0/12'
      ]
    }
    subnets: [
      {
        name: infraSubnetName
        properties: {
          addressPrefix: '10.224.0.0/16'
        }
      }
      {
        name: 'pe-subnet'
        properties:{
          addressPrefix: '10.225.0.0/24'
        }
      }
      {
        name: aciSubnetName
        properties:{
          addressPrefix: '10.225.1.0/24'
          natGateway: {
            id: aciNatGw.id
          }
          delegations: [
            {
              name: 'aci'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
        }
      }
    ]
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' ={
  name: 'pe-subnetdelegator-${uniqueString(subnetDelegatorName)}'
  location: region
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'pe-subnetdelegator-${uniqueString(subnetDelegatorName)}-connection'
        properties: {
          privateLinkServiceId: subnetDelegatorAcaEnv.id
          groupIds: [
            'managedEnvironments'
          ]
        }
      }
    ]
    subnet: {
      id: infraVnet.properties.subnets[1].id
    }
  }
}

resource customerVnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'customerVnet'
  location: region
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: delegatedSubnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: 'dnc'
              properties: {
                serviceName: 'Microsoft.SubnetDelegator/msfttestclients'
              }
            }
          ]
        }
      }
      {
        name: delegatedSubnet1Name
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'dnc1'
              properties: {
                serviceName: 'Microsoft.SubnetDelegator/msfttestclients'
              }
            }
          ]
        }
      }
    ]
  }
}

resource cluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: region
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      //'/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/standalone-nightly-pipeline/providers/Microsoft.ManagedIdentity/userAssignedIdentities/standalone-sub-contributor': {}
      // '/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/dala-aks-runner8/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aksClusterKubeletIdentity': {}
      '${aksClusterKubeletIdentity.id}': {}
    }
  }
  properties: {
    

    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }

    agentPoolProfiles: [
      {
        count: 1
        enableAutoScaling: false
        enableEncryptionAtHost: false
        enableNodePublicIP: false
        mode: 'System'
        name: 'dncpool0'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vmSize: 'Standard_D2_v2'
        vnetSubnetID: infraVnet.properties.subnets[0].id
      }
      {
        count: 1
        enableAutoScaling: false
        enableEncryptionAtHost: false
        enableNodePublicIP: false
        mode: 'User'
        name: 'linuxpool0'
        nodeLabels: {
          nchost: 'true'
        }
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vmSize: 'Standard_D2_v2'
        vnetSubnetID: infraVnet.properties.subnets[0].id
      }
    ]
    dnsPrefix: clusterName
    identityProfile: {
      kubeletidentity: {
        // resourceId: '/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/standalone-nightly-pipeline/providers/Microsoft.ManagedIdentity/userAssignedIdentities/standalone-sub-contributor'
        // resourceId: '/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/dala-aks-runner8/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aksClusterKubeletIdentity'
        resourceId: aksClusterKubeletIdentity.id
        clientId: '8134a3dc-ad2c-486b-adeb-a4ff75cb55c5'
        objectId: '71c8ae14-0aa4-4962-a1ef-46aff516a9ee'
      }
    }
    networkProfile: {
      loadBalancerProfile: {
        outboundIPs: {
          publicIPs: [
            {
              id: outboundIp.id
            }
          ]
        }
      }

      networkMode: 'transparent'
      networkPlugin: 'azure'
    }
  }
}



resource cosmosdb 'Microsoft.DocumentDB/databaseAccounts@2022-05-15' = {
  name: cosmosdbName
  location: region
  kind: 'GlobalDocumentDB'
  properties: {
    enableMultipleWriteLocations: false
    enableAutomaticFailover: false
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    capabilities: [
      {
        name: 'EnableTable'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
      maxIntervalInSeconds: 5
      maxStalenessPrefix: 100
    }
    locations: [
      {
        locationName: region
        provisioningState: 'Succeeded'
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}


resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'helm-script-msi3'
  location: region
}

module roleAssignments1 './roleAssignmentsInSub.bicep' = {
  name: 'roleAssignmentsDeployment1'
  scope: subscription() // Explicitly set the module scope to subscription
  params: {
    principalId: userAssignedIdentity.properties.principalId
  }
}

resource storageFileDataPrivilegedContributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '69566ab7-960f-475b-8e7c-b3118f30c6bd' // Storage File Data Privileged Contributor
  scope: tenant()
}

resource dsStorage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: 'dsstorage${uniqueString(resourceGroup().name)}'
  location: region
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dsStorage

  name: guid(storageFileDataPrivilegedContributor.id, userAssignedIdentity.id, dsStorage.id)
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: storageFileDataPrivilegedContributor.id
    principalType: 'ServicePrincipal'
  }
}

resource storageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dsStorage
  name: guid('17d1049b-9a84-46fb-8f53-869881c3d3ab', userAssignedIdentity.id, dsStorage.id)
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalType: 'ServicePrincipal'
  }
}

module testResourcesModule './testResources.bicep' = {
  name: 'testResourcesDeployment'
  params: {
    region: region
  }
}

output fqdn1 string = testResourcesModule.outputs.fqdn1
output fqdn2 string = testResourcesModule.outputs.fqdn2

param randomGuid string = newGuid()

// Subnet delegation script
resource ds 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  #disable-next-line use-stable-resource-identifiers
  name: 'ds-subnetdelegator-${uniqueString(resourceGroup().name)}' 
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  dependsOn: [
    customerVnet
    roleAssignment
    storageContributor
  ]
  location: region
  properties: {
    storageAccountSettings: {storageAccountName: dsStorage.name}
    containerSettings: {
      subnetIds: [
        {
          id: infraVnet.properties.subnets[2].id
        }
      ]
    }
    azCliVersion: '2.69.0'
    forceUpdateTag: randomGuid
    retentionInterval: 'PT2H'
    cleanupPreference: 'OnExpiration'
    timeout: 'PT20M'
    scriptContent: concat(
      'curl -X PUT ${privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]}:${subnetDelegator.properties.configuration.ingress.exposedPort}/VirtualNetwork/%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${resourceGroup().name}%2Fproviders%2FMicrosoft.Network%2FvirtualNetworks%2F${infraVnetName};',
      'resp=$(curl -X PUT ${privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]}:${subnetDelegator.properties.configuration.ingress.exposedPort}/DelegatedSubnet/%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${resourceGroup().name}%2Fproviders%2FMicrosoft.Network%2FvirtualNetworks%2F${customerVnetName}%2Fsubnets%2F${delegatedSubnetName});',
      'token=$(echo "$resp" | grep -oP \'(?<=\\{).*?(?=\\})\' | sed -n \'s/.*"primaryToken":"\\([^"]*\\)".*/\\1/p\');',
      'resp1=$(curl -X PUT ${privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]}:${subnetDelegator.properties.configuration.ingress.exposedPort}/DelegatedSubnet/%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${resourceGroup().name}%2Fproviders%2FMicrosoft.Network%2FvirtualNetworks%2F${customerVnetName}%2Fsubnets%2F${delegatedSubnet1Name});',
      'token1=$(echo "$resp1" | grep -oP \'(?<=\\{).*?(?=\\})\' | sed -n \'s/.*"primaryToken":"\\([^"]*\\)".*/\\1/p\');',
      'echo "{\\"salToken\\":\\"$token\\",\\"salToken1\\":\\"$token1\\"}" > $AZ_SCRIPTS_OUTPUT_PATH;',
      'cat $AZ_SCRIPTS_OUTPUT_PATH;'
    )
  }
}


// Outputs
output salToken string = ds.properties.outputs.salToken
output salToken1 string = ds.properties.outputs.salToken1

// Execute script
resource aksBYNOScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  #disable-next-line use-stable-resource-identifiers
  name: 'aksBYONScript' 
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  location: region
  dependsOn: [
    cluster
    testResourcesModule
  ]
  properties: {
    azCliVersion: '2.60.0'
    forceUpdateTag: randomGuid
    retentionInterval: 'PT2H'
    cleanupPreference: 'OnExpiration'
    timeout: 'PT20M'
    primaryScriptUri: 'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/aksBYON.sh'
    arguments: '-g ${rg} -c ${clusterName} -u ${subscriptionId}'
    supportingScriptUris: [
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/Chart.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/values.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/cni-plugins-installer.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/cns-unmanaged-windows.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/cns-unmanaged.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/azure_cni_daemonset.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/azure_cns_configmap.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/dnc_deployment.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/azure_cns_daemonset.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/bootstrap-role.yaml'
    ]
  }
  // tags: {
  //   'Az.Sec.DisableLocalAuth.Storage::Skip': 'Temporary bypass for deployment'
  // }
}




module dncVmssCreation 'vmssCreation.bicep' = {
  name: 'vmssCreationModule'
  params: {
    vnetResourceGroupName: rg
    infraVnetName: infraVnetName
    infraSubnetName: infraSubnetName
    vmssNames: dncVMSSNames
    aksClusterKubeletIdentityId: aksClusterKubeletIdentity.id
  }
  dependsOn: [aksBYNOScript]
}

output dncVMSSLogs array = dncVmssCreation.outputs.vmssDeploymentLogs

module workerVmssCreation 'vmssCreation.bicep' = {
  name: 'workerVmssCreationModule'
  params: {
    vnetResourceGroupName: rg
    infraVnetName: infraVnetName
    infraSubnetName: infraSubnetName
    vmssNames: workerVMSSNames
    aksClusterKubeletIdentityId: aksClusterKubeletIdentity.id
  }
  dependsOn: [aksBYNOScript]
}

output workerVMSSLogs array = workerVmssCreation.outputs.vmssDeploymentLogs

resource installSwiftScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  #disable-next-line use-stable-resource-identifiers
  name: 'installSwiftScript' 
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  location: region
  dependsOn: [
    cluster
    testResourcesModule
    workerVmssCreation
    dncVmssCreation
  ]
  properties: {
    azCliVersion: '2.60.0'
    forceUpdateTag: randomGuid
    retentionInterval: 'PT2H'
    cleanupPreference: 'OnExpiration'
    timeout: 'PT30M'
    primaryScriptUri: 'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/installSwift.sh'
    arguments: '-g ${rg} -c ${clusterName} -u ${subscriptionId} -v ${infraVnetName} -t "${ds.properties.outputs.salToken}|${ds.properties.outputs.salToken1}" -V ${customerVnet.properties.resourceGuid} -d ${cosmosdbName} -W ${join(workerVMSSNames, ',')} -D ${join(dncVMSSNames, ',')} -N ${customerVnetName}'
    supportingScriptUris: [
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/Chart.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/values.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/cni-plugins-installer.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/cns-unmanaged-windows.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/cns-unmanaged.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/azure_cni_daemonset.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/azure_cns_configmap.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/dnc_deployment.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/azure_cns_daemonset.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/dnc_configmap.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/test.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/dnc_configmap_pubsubproxy.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/container1.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/container2.yaml'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/roleAssignmentsInSub.bicep'
    ]
  }
  // tags: {
  //   'Az.Sec.DisableLocalAuth.Storage::Skip': 'Temporary bypass for deployment'
  // }
}


output privateIPs array = installSwiftScript.properties.outputs.privateIPs
output subnetIds array = installSwiftScript.properties.outputs.subnetIDs



// Cleanup script
resource dsGc 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  #disable-next-line use-stable-resource-identifiers
  name: 'ds-gc-${uniqueString(resourceGroup().name)}' 
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  dependsOn: [
    ds
    storageContributor
  ]
  location: region
  properties: {
    azCliVersion: '2.69.0'
    forceUpdateTag: randomGuid
    retentionInterval: 'PT2H'
    cleanupPreference: 'Always'
    timeout: 'PT20M'
    scriptContent: concat(
      'az account set -s ${subscription().subscriptionId};',
      'az storage account delete --name ${dsStorage.name} -y;'
    )
  }
}



