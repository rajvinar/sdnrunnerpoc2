@description('Name of the infrastructure VNet')
param infraVnetName string

@description('Name of the infrastructure subnet')
param infraSubnetName string

@description('Admin password for the VMSS')
param adminPassword string = '123aA!'

@description('Location for the deployment')
param location string = resourceGroup().location

@description('Array of DNC VMSS names')
param vmssNames array

@description('Bicep template path for VMSS deployment')
param bicepTemplatePath string = 'linux.bicep'

@description('SKU for the VMSS')
param vmssSku string = 'Standard_E8s_v3'

@description('Extension name prefix for the VMSS')
param extensionNamePrefix string = 'NodeJoin'

@description('Unique deployment name prefix')
param deploymentNamePrefix string = 'vmss-deployment'

@description('Resource group name for the VNet')
param vnetResourceGroupName string

@description('Log file path for VMSS deployment')
param logFilePath string = './'

@description('Enable logging for VMSS deployment')
param enableLogging bool = true

param aksClusterKubeletIdentityId string

module vmssDeployments './linux.bicep' = [for vmssName in vmssNames: {
  name: '${deploymentNamePrefix}-${vmssName}'
  params: {
    vnetname: infraVnetName
    subnetname: infraSubnetName
    name: vmssName
    adminPassword: adminPassword
    vnetrgname: vnetResourceGroupName
    vmsssku: vmssSku
    location: location
    extensionName: '${extensionNamePrefix}-${vmssName}'
    aksClusterKubeletIdentityId: '${aksClusterKubeletIdentityId}'
  }
}]

output vmssDeploymentLogs array = [for vmssName in vmssNames: {
  name: vmssName
  logFile: enableLogging ? '${logFilePath}/lin-script-${vmssName}.log' : null
}]
