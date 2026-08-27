// Azure API Management como AI Gateway (SKU Developer, el más barato con todas las políticas LLM).
// Solo crea el servicio + logger + diagnóstico. La API la añade modules/ai-gateway-api.bicep.
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
    resourceId: ''
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

output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
output loggerName string = appiLogger.name
