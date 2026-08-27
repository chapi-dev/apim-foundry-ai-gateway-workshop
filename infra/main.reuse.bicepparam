using './main.reuse.bicep'

// Reutiliza el AI Gateway StandardV2 existente (eastus) y sus Foundry del workshop (Sweden).
param existingApimName = 'apim-aigw-dev-01'
param existingApimResourceGroup = 'rg-aigateway-dev-01'
param existingApimPrincipalId = 'd668e208-643b-46e7-b9a1-0d572374a032'
param existingLoggerName = 'appi-aigw-dev-01'
param foundryAccountNames = [
  'aigwqyxvxaoai1'
  'aigwqyxvxaoai2'
]
