// Cuenta de Azure AI Foundry (Azure OpenAI) con despliegues de modelos.
// Se despliega una vez por cada backend para poder demostrar balanceo de carga.
@description('Nombre de la cuenta (Azure OpenAI / AI Services)')
param name string

@description('Región')
param location string

param tags object = {}

@description('Desplegar también un modelo de embeddings (para semantic cache)')
param deployEmbeddings bool = false

@description('Nombre del despliegue del modelo de chat')
param chatDeploymentName string = 'chat'

@description('Modelo de chat')
param chatModelName string = 'gpt-4.1-mini'

@description('Versión del modelo de chat')
param chatModelVersion string = '2025-04-14'

@description('Capacidad (miles de TPM) del modelo de chat')
param chatCapacity int = 20

@description('Nombre del despliegue de embeddings')
param embeddingsDeploymentName string = 'embeddings'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    // Solo Entra ID / Managed Identity: desactiva autenticación por clave para forzar keyless.
    disableLocalAuth: false
  }
}

resource chat 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: chatDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
  }
}

resource embeddings 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployEmbeddings) {
  parent: account
  name: embeddingsDeploymentName
  dependsOn: [
    chat
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
  }
}

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output chatDeployment string = chatDeploymentName
output embeddingsDeployment string = deployEmbeddings ? embeddingsDeploymentName : ''
