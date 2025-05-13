@description('The principal ID of the identity to assign roles to')
param principalId string
targetScope = 'subscription'

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'Contributor')
  scope: subscription() // Set the scope to the subscription level
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor Role
    principalType: 'ServicePrincipal'
  }
}

module acrPullRoleAssignmentModule './acrPullRoleAssignment.bicep' = {
  name: guid('0895de50-30a3-4b75-aada-5b23ebd4e8bc', principalId, 'AcrPull')
  scope: subscription('0895de50-30a3-4b75-aada-5b23ebd4e8bc')
  params: {
    principalId: principalId
  }
}

resource keyVaultAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'KeyVaultAdmin')
  scope: subscription() // Set the scope to the subscription level
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Administrator Role
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultCertUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'KeyVaultCertUser')
  scope: subscription() // Set the scope to the subscription level
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985') // Key Vault Certificate User Role
    principalType: 'ServicePrincipal'
  }
}

resource networkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'NetworkContributor')
  scope: subscription() // Set the scope to the subscription level
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource storageFileDataPrivilegedContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'StorageFileDataPrivilegedContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69566ab7-960f-475b-8e7c-b3118f30c6bd') // Storage File Data Privileged Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'StorageAccountContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource aksRbacAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AksRbacAdmin')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3498e952-d568-435e-9b2c-8d77e338d7f7') // Azure Kubernetes Service RBAC Admin Role
    principalType: 'ServicePrincipal'
  }
}

resource aksClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AksClusterAdmin')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8') // Azure Kubernetes Service Cluster Admin Role
    principalType: 'ServicePrincipal'
  }
}

resource managedIdentityOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'ManagedIdentityOperator')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f1a07417-d97a-45cb-824c-7a7467783830') // Managed Identity Operator Role
    principalType: 'ServicePrincipal'
  }
}

resource vmContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'VmContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c') // Virtual Machine Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource managedIdentityContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'ManagedIdentityContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e40ec5ca-96e0-45a2-b4ff-59039f2c2b59') // Managed Identity Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource aksRbacReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AksRbacReader')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f6c6a51-bcf8-42ba-9220-52d62157d7db') // Azure Kubernetes Service RBAC Reader Role
    principalType: 'ServicePrincipal'
  }
}

resource aksContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AksContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8') // Azure Kubernetes Service Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'Reader')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader Role
    principalType: 'ServicePrincipal'
  }
}

resource ownerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'Owner')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635') // Owner Role
    principalType: 'ServicePrincipal'
  }
}
