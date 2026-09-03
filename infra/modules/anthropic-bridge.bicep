// Puente Anthropic -> Azure OpenAI dentro de APIM, SIN LiteLLM.
//
// Expone la Anthropic Messages API (/v1/messages) sobre los mismos backends de Foundry que
// usa la API "ai-gateway": el cliente (Claude Code) sigue hablando protocolo Anthropic y la
// traducción de formato la hace la política del gateway.
//
// Requiere que el módulo ai-gateway-api.bicep se haya aplicado antes, porque reutiliza su
// pool de backends (aoai-pool) y su producto (ai-workshop).
@description('Nombre del servicio APIM ya existente en este resource group')
param apimName string

@description('Nombre del producto de APIM al que se enlaza la API')
param productName string = 'ai-workshop'

@description('Despliegue de Foundry usado cuando el cliente pide un modelo claude-*')
param defaultDeployment string = 'chat'

@description('Despliegues de Foundry que se anuncian en GET /v1/models (separados por comas)')
param advertisedModels string = 'chat'

@description('Límite de tokens por minuto y suscripción. Muy por encima del de la API de demo: el system prompt de Claude Code, con todas sus herramientas, ronda los 10-15k tokens por petición.')
param tokensPerMinute int = 200000

@description('Nombre de un logger de Application Insights ya existente en el APIM. Vacío = sin diagnóstico.')
param loggerName string = ''

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

resource product 'Microsoft.ApiManagement/service/products@2024-06-01-preview' existing = {
  parent: apim
  name: productName
}

// Valores con nombre que consumen las políticas ({{...}})
resource nvDefaultModel 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'anthropic-bridge-default-model'
  properties: {
    displayName: 'anthropic-bridge-default-model'
    value: defaultDeployment
    secret: false
  }
}

resource nvModels 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'anthropic-bridge-models'
  properties: {
    displayName: 'anthropic-bridge-models'
    value: advertisedModels
    secret: false
  }
}

resource nvTpm 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'anthropic-bridge-tpm'
  properties: {
    displayName: 'anthropic-bridge-tpm'
    value: string(tokensPerMinute)
    secret: false
  }
}

// API que habla protocolo Anthropic de cara al cliente.
// La clave de suscripción viaja en x-api-key, que es la cabecera nativa de Anthropic:
// así el cliente no necesita ninguna cabecera especial.
resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: 'anthropic-bridge'
  properties: {
    displayName: 'Anthropic bridge (Claude Code -> Foundry)'
    description: 'Anthropic Messages API traducida a Azure OpenAI en el gateway, sin LiteLLM'
    path: 'claude'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'x-api-key'
      query: 'api-key'
    }
    type: 'http'
  }
}

resource opMessages 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'create-message'
  properties: {
    displayName: 'Create message'
    method: 'POST'
    urlTemplate: '/v1/messages'
    responses: [
      {
        statusCode: 200
        description: 'Anthropic message'
      }
    ]
  }
}

resource opCountTokens 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'count-tokens'
  properties: {
    displayName: 'Count message tokens'
    method: 'POST'
    urlTemplate: '/v1/messages/count_tokens'
    responses: [
      {
        statusCode: 200
        description: 'Token estimate'
      }
    ]
  }
}

resource opModels 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'list-models'
  properties: {
    displayName: 'List models'
    method: 'GET'
    urlTemplate: '/v1/models'
    responses: [
      {
        statusCode: 200
        description: 'Available deployments'
      }
    ]
  }
}

resource policyMessages 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: opMessages
  name: 'policy'
  dependsOn: [
    nvDefaultModel
    nvTpm
  ]
  properties: {
    value: loadTextContent('../policies/anthropic-messages-policy.xml')
    format: 'rawxml'
  }
}

resource policyCountTokens 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: opCountTokens
  name: 'policy'
  properties: {
    value: loadTextContent('../policies/anthropic-count-tokens-policy.xml')
    format: 'rawxml'
  }
}

resource policyModels 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: opModels
  name: 'policy'
  dependsOn: [
    nvModels
  ]
  properties: {
    value: loadTextContent('../policies/anthropic-models-policy.xml')
    format: 'rawxml'
  }
}

// Mismo producto que la API nativa: la misma clave de suscripción sirve para las dos.
resource productApi 'Microsoft.ApiManagement/service/products/apiLinks@2024-06-01-preview' = {
  parent: product
  name: 'anthropic-bridge-link'
  properties: {
    apiId: api.id
  }
}

// Métricas de tokens de Claude Code en el mismo Application Insights
resource apiDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if (!empty(loggerName)) {
  parent: api
  name: 'applicationinsights'
  properties: {
    loggerId: resourceId('Microsoft.ApiManagement/service/loggers', apimName, loggerName)
    alwaysLog: 'allErrors'
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
  }
}

output apiPath string = api.properties.path
