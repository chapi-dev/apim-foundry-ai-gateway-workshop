// AI Gateway Workshop - MODO REUTILIZACIÓN
// Aplica la API del workshop sobre un APIM YA EXISTENTE y da a su Managed Identity permiso
// keyless sobre los Foundry indicados. No crea APIM ni monitorización nuevos.
//
// Se despliega en el resource group donde viven las cuentas de Foundry.
targetScope = 'resourceGroup'

@description('Nombre del APIM existente a reutilizar')
param existingApimName string

@description('Resource group del APIM existente')
param existingApimResourceGroup string

@description('PrincipalId de la Managed Identity del APIM existente')
param existingApimPrincipalId string

@description('Nombre de un logger de Application Insights ya presente en el APIM (para métricas). Vacío = sin diagnóstico.')
param existingLoggerName string = ''

@description('Nombres de las cuentas de Foundry (en este resource group) a usar como backends')
param foundryAccountNames array

resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = [
  for n in foundryAccountNames: {
    name: n
  }
]

// Rol "Cognitive Services OpenAI User" para la MI del APIM sobre cada Foundry
module roles 'modules/roleAssignment.bicep' = [
  for (n, i) in foundryAccountNames: {
    name: 'role-${n}'
    params: {
      accountName: n
      principalId: existingApimPrincipalId
    }
  }
]

// Añade la API del AI Gateway al APIM existente (en su propio resource group)
module aiApi 'modules/ai-gateway-api.bicep' = {
  scope: resourceGroup(existingApimResourceGroup)
  name: 'ai-gateway-api-reuse'
  params: {
    apimName: existingApimName
    loggerName: existingLoggerName
    foundryEndpoints: [
      for i in range(0, length(foundryAccountNames)): foundry[i].properties.endpoint
    ]
  }
}

output apimName string = existingApimName
