# Obtiene endpoint y clave del AI Gateway.
# Modo greenfield:  ./get-keys.ps1                       (lee outputs del despliegue aigw-core)
# Modo reutilización: ./get-keys.ps1 -ApimName apim-aigw-dev-01 -ResourceGroup rg-aigateway-dev-01
param(
    [string]$ApimName,
    [string]$ResourceGroup = "rg-apim-workshop",
    [string]$DeploymentName = "aigw-core",
    [string]$SubscriptionId = "ai-workshop-sub"
)

$ErrorActionPreference = "Stop"
$sub = az account show --query id -o tsv

if (-not $ApimName) {
    # Greenfield: sacar el nombre del APIM del despliegue
    $out = az deployment group show -g $ResourceGroup -n $DeploymentName --query properties.outputs -o json | ConvertFrom-Json
    $ApimName = $out.apimName.value
}

$apimRg = $ResourceGroup
# Si el APIM no está en $ResourceGroup, localízalo
$found = az apim show -g $apimRg -n $ApimName --query name -o tsv 2>$null
if (-not $found) {
    $apimRg = az resource list --resource-type Microsoft.ApiManagement/service --query "[?name=='$ApimName'].resourceGroup | [0]" -o tsv
}

$gw = az apim show -g $apimRg -n $ApimName --query "properties.gatewayUrl" -o tsv
if (-not $gw) { $gw = "https://$ApimName.azure-api.net" }

$key = az rest --method post `
    --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$apimRg/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$SubscriptionId/listSecrets?api-version=2024-06-01-preview" `
    --query primaryKey -o tsv

Write-Host "APIM                  = $ApimName ($apimRg)"
Write-Host "APIM_GATEWAY_URL      = $gw"
Write-Host "APIM_SUBSCRIPTION_KEY = $key"
Write-Host ""
Write-Host "Para PowerShell:" -ForegroundColor Cyan
Write-Host "  `$env:APIM_GATEWAY_URL=`"$gw`""
Write-Host "  `$env:APIM_SUBSCRIPTION_KEY=`"$key`""
