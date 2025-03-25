@description('Name of the cluster')
param clusterName string
@description('Region')
param region string
@description('Resource Group')
param rg string
@description('Name of the cosmosdb')
param cosmosdbName string

var vnetName = 'infraVnet'
var subnetName = 'infraSubnet'

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

resource infraVnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'infraVnet'
  location: region
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.224.0.0/12'
      ]
    }
    subnets: [
      {
        name: 'infraSubnet'
        properties: {
          addressPrefix: '10.224.0.0/16'
        }
      }
    ]
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
        name: 'delegatedSubnet'
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
    ]
  }
}

resource cluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: region
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/standalone-nightly-pipeline/providers/Microsoft.ManagedIdentity/userAssignedIdentities/standalone-sub-contributor': {}
    }
  }
  properties: {
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
        resourceId: '/subscriptions/9b8218f9-902a-4d20-a65c-e98acec5362f/resourceGroups/standalone-nightly-pipeline/providers/Microsoft.ManagedIdentity/userAssignedIdentities/standalone-sub-contributor'
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


resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = {
  name: 'helm-script-msi-${uniqueString(subscription().id)}'
  //location: region
}

// resource aksRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
//   name: '3498e952-d568-435e-9b2c-8d77e338d7f1'
//   scope: resourceGroup()
//   properties: {
//     principalId: userAssignedIdentity.properties.principalId
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3498e952-d568-435e-9b2c-8d77e338d7f7')//Azure Kubernetes Service RBAC Admin
//   }
// }

param randomGuid string = newGuid()

// Execute script
resource helmScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  #disable-next-line use-stable-resource-identifiers
  name: 'helmDeploymentScript' 
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
  ]
  properties: {
    azCliVersion: '2.0.80'
    forceUpdateTag: randomGuid
    retentionInterval: 'PT2H'
    cleanupPreference: 'OnExpiration'
    timeout: 'PT20M'
    //scriptContent: 'curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash;az account set -s ${subscriptionId};az aks get-credentials --resource-group ${rg} --name ${clusterName};helm repo add stable https://charts.helm.sh/stable;helm repo update;helm install goldpinger stable/goldpinger --namespace default;'
    primaryScriptUri: 'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/joinVMSS.sh'
    arguments: '-g ${rg} -c ${clusterName} -b liunx.bicep -p 123 -v ${vnetName} -s ${subnetName} -n ${rg}'
    supportingScriptUris: [
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/linux.bicep'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/provisionscript.bicep'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/clouds.bicep'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/common/cacert.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/common/config.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/common/containerd.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/common/delayext-and-waitdnsready.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/common/kubelet-msi.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/common/kubelet.sh'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/scripts/provisionscript-manual/provisionscript.ps1'
      'https://raw.githubusercontent.com/danlai-ms/dan-test/refs/heads/main/bootstrap-role.yaml'
    ]
  }
  tags: {
    'Az.Sec.DisableLocalAuth.Storage::Skip': 'Temporary bypass for deployment'
  }
}
