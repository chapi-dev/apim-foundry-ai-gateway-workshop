// Azure API Management como AI Gateway (SKU Developer, el más barato con todas las políticas LLM).
@description('Nombre del servicio APIM (único globalmente)')
param name string

param location string
param tags object = {}

@description('SKU de APIM. Developer = más barato con soporte de políticas LLM (sin SLA).')
@allowed([
  'Developer'
  'BasicV2'
  'StandardV2'
])
param skuName string = 'Developer'

param publisherName string = 'APIM AI Gateway Workshop'
param publisherEmail string = 'admin@contoso.com'

@description('Connection string de Application Insights (para el logger de métricas)')
param appInsightsConnectionString string

@description('Endpoints de los backends de Foundry (https://xxx.openai.azure.com/)')
param foundryEndpoints array

var aiApiPolicy = loadTextContent('../policies/ai-api-policy.xml')

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
  }
}

// Logger de Application Insights (necesario para llm-emit-token-metric)
resource appiLogger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: '' // opcional
    credentials: {
      connectionString: appInsightsConnectionString
    }
  }
}

// Diagnóstico a nivel de servicio: habilita logging y métricas personalizadas (tokens)
resource serviceDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-06-01-preview' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: appiLogger.id
    alwaysLog: 'allErrors'
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
  }
}

// Un backend individual por cada despliegue de Foundry, con circuit breaker.
resource backends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [
  for (endpoint, i) in foundryEndpoints: {
    parent: apim
    name: 'aoai-${i}'
    properties: {
      description: 'Azure AI Foundry backend ${i}'
      url: '${endpoint}openai'
      protocol: 'http'
      circuitBreaker: {
        rules: [
          {
            failureCondition: {
              count: 3
              interval: 'PT1M'
              statusCodeRanges: [
                {
                  min: 429
                  max: 429
                }
                {
                  min: 500
                  max: 599
                }
              ]
            }
            name: 'openai-breaker'
            tripDuration: 'PT30S'
            acceptRetryAfter: true
          }
        ]
      }
    }
  }
]

// Pool de backends para balanceo de carga / failover.
resource pool 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: 'aoai-pool'
  dependsOn: [
    backends
  ]
  properties: {
    description: 'Pool de backends de Azure AI Foundry'
    type: 'Pool'
    pool: {
      services: [
        for (endpoint, i) in foundryEndpoints: {
          id: '/backends/aoai-${i}'
          priority: 1
          weight: 1
        }
      ]
    }
  }
}

// API del AI Gateway (compatible Azure OpenAI: /openai/deployments/{d}/...)
resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: 'ai-gateway'
  properties: {
    displayName: 'AI Gateway (Foundry)'
    description: 'Puerta de enlace gobernada hacia Azure AI Foundry'
    path: 'openai'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    type: 'http'
    format: 'openapi+json'
    value: loadTextContent('../policies/openai-openapi.json')
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: api
  name: 'policy'
  dependsOn: [
    pool
    appiLogger
  ]
  properties: {
    value: aiApiPolicy
    format: 'rawxml'
  }
}

// Producto + suscripción para obtener claves de demo
resource product 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = {
  parent: apim
  name: 'ai-workshop'
  properties: {
    displayName: 'AI Workshop'
    description: 'Producto de demo para el AI Gateway'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apiLinks@2024-06-01-preview' = {
  parent: product
  name: 'ai-gateway-link'
  properties: {
    apiId: api.id
  }
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = {
  parent: apim
  name: 'ai-workshop-sub'
  properties: {
    displayName: 'AI Workshop Subscription'
    scope: product.id
    state: 'active'
  }
}

output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
