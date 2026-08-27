// Añade la API del AI Gateway (backends + pool + política + producto + suscripción) a un
// servicio APIM EXISTENTE o recién creado. Reutilizable en greenfield y en modo reutilización.
@description('Nombre del servicio APIM ya existente en este resource group')
param apimName string

@description('Endpoints de los backends de Foundry (https://xxx.openai.azure.com/)')
param foundryEndpoints array

@description('Nombre de un logger de Application Insights ya existente en el APIM (para métricas). Vacío = sin diagnóstico.')
param loggerName string = ''

var aiApiPolicy = loadTextContent('../policies/ai-api-policy.xml')

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
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
    description: 'Puerta de enlace gobernada hacia Azure AI Foundry (workshop)'
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
  ]
  properties: {
    value: aiApiPolicy
    format: 'rawxml'
  }
}

// Diagnóstico a nivel de API (métricas de tokens) usando un logger existente.
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

output apiPath string = api.properties.path
