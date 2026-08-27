// Log Analytics + Application Insights para métricas de tokens/costes del AI Gateway
@description('Prefijo de nombres')
param prefix string

@description('Región')
param location string

param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-appi'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    IngestionMode: 'LogAnalytics'
  }
}

output lawId string = law.id
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
