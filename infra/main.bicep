// AI Gateway Workshop - despliegue del núcleo (RG scope)
// Foundry (2x Azure OpenAI) + APIM Developer (AI Gateway) + Monitorización + Managed Identity keyless
targetScope = 'resourceGroup'

@description('Prefijo corto para nombrar recursos (minúsculas)')
param prefix string = 'aigw'

@description('Sufijo único (por defecto derivado del RG)')
param suffix string = substring(uniqueString(resourceGroup().id), 0, 5)

@description('Región de despliegue')
param location string = resourceGroup().location

@description('SKU de APIM')
@allowed([
  'Developer'
  'BasicV2'
  'StandardV2'
])
param apimSku string = 'Developer'

param publisherEmail string = 'admin@contoso.com'

var tags = {
  workshop: 'apim-foundry-ai-gateway'
  env: 'demo'
}

var namePrefix = '${prefix}-${suffix}'

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    prefix: namePrefix
    location: location
    tags: tags
  }
}

// Backend 1 (con embeddings para semantic cache)
module foundry1 'modules/foundry.bicep' = {
  name: 'foundry1'
  params: {
    name: '${prefix}${suffix}aoai1'
    location: location
    tags: tags
    deployEmbeddings: true
  }
}

// Backend 2 (para demostrar balanceo de carga / failover)
module foundry2 'modules/foundry.bicep' = {
  name: 'foundry2'
  params: {
    name: '${prefix}${suffix}aoai2'
    location: location
    tags: tags
    deployEmbeddings: true
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    name: '${namePrefix}-apim'
    location: location
    tags: tags
    skuName: apimSku
    publisherEmail: publisherEmail
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// Añade la API del AI Gateway (backends + pool + política) al APIM recién creado
module aiApi 'modules/ai-gateway-api.bicep' = {
  name: 'ai-gateway-api'
  params: {
    apimName: apim.outputs.name
    loggerName: apim.outputs.loggerName
    foundryEndpoints: [
      foundry1.outputs.endpoint
      foundry2.outputs.endpoint
    ]
  }
}

// Managed Identity de APIM con permiso keyless sobre ambos Foundry
module role1 'modules/roleAssignment.bicep' = {
  name: 'role-aoai1'
  params: {
    accountName: foundry1.outputs.name
    principalId: apim.outputs.principalId
  }
}

module role2 'modules/roleAssignment.bicep' = {
  name: 'role-aoai2'
  params: {
    accountName: foundry2.outputs.name
    principalId: apim.outputs.principalId
  }
}

output apimName string = apim.outputs.name
output gatewayUrl string = apim.outputs.gatewayUrl
output chatDeployment string = foundry1.outputs.chatDeployment
output embeddingsDeployment string = foundry1.outputs.embeddingsDeployment
output foundry1Name string = foundry1.outputs.name
output foundry2Name string = foundry2.outputs.name
output appInsightsName string = monitoring.outputs.appInsightsName
