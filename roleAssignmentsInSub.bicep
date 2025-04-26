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

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AcrPull')
  scope: subscription() // Set the scope to the subscription level
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull Role
    principalType: 'ServicePrincipal'
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
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'eabd9c6f-8c9f-4d7e-8e7c-8d7e8e7c8d7e') // Network Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource storageFileDataPrivilegedContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'StorageFileDataPrivilegedContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f4c5831-68a9-4d15-b62f-a9d9e5309b97') // Storage File Data Privileged Contributor Role
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
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e4a2ae05-4b1a-4c18-b9e4-2a3ade6e82b7') // Azure Kubernetes Service RBAC Admin Role
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
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '998b4e8f-9f1e-4dc0-8c7e-5d63b7de9f4b') // Virtual Machine Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource managedIdentityContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'ManagedIdentityContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b') // Managed Identity Contributor Role
    principalType: 'ServicePrincipal'
  }
}

resource aksRbacReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AksRbacReader')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e5a5b6f6-7c8e-4f5b-8b3e-3f3e8e7c8d7e') // Azure Kubernetes Service RBAC Reader Role
    principalType: 'ServicePrincipal'
  }
}

resource aksContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AksContributor')
  scope: subscription()
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fdfdfdfd-1234-5678-9abc-123456789abc') // Azure Kubernetes Service Contributor Role
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
