// Asigna "Cognitive Services OpenAI User" a un principal sobre una cuenta de Foundry
param accountName string
param principalId string

var openAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, principalId, openAiUserRoleId)
  properties: {
    roleDefinitionId: openAiUserRoleId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
