@description('The principal ID of the identity to assign roles to')
param principalId string
targetScope = 'subscription'

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'AcrPull')
  scope: subscription() // Set the scope to the subscription level
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull Role
    principalType: 'ServicePrincipal'
  }
}
