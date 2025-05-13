@description('Name of the infrastructure VNet')
param vnetName string

@description('Name of the infrastructure subnet')
param subnetName string

@description('Name of the VMSS')
param vmssName string

@description('Admin password for the VMSS')
param adminPassword string

@description('Resource group name for the VNet')
param vnetResourceGroupName string

@description('SKU for the VMSS')
param vmssSku string

@description('Location for the deployment')
param location string

@description('Extension name for the VMSS')
param extensionName string

@description('Bicep template path for VMSS deployment')
param bicepTemplatePath string

resource vmssDeployment 'Microsoft.Resources/deployments@2021-04-01' = {
  name: '${vmssName}-deployment'
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: bicepTemplatePath
    }
    parameters: {
      vnetname: vnetName
      subnetname: subnetName
      name: vmssName
      adminPassword: adminPassword
      vnetrgname: vnetResourceGroupName
      vmsssku: vmssSku
      location: location
      extensionName: extensionName
    }
  }
}
