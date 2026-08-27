# Obtiene los datos de conexión del AI Gateway desplegado.
param(
    [string]$ResourceGroup = "rg-apim-workshop",
    [string]$DeploymentName = "aigw-core"
)

$ErrorActionPreference = "Stop"

$out = az deployment group show -g $ResourceGroup -n $DeploymentName --query properties.outputs -o json | ConvertFrom-Json
$apimName = $out.apimName.value
$gatewayUrl = $out.gatewayUrl.value

$key = az apim subscription show -g $ResourceGroup --service-name $apimName --sid "ai-workshop-sub" --query primaryKey -o tsv 2>$null
if (-not $key) {
    # Fallback vía REST si el comando no está disponible
    $key = az rest --method post `
        --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/ai-workshop-sub/listSecrets?api-version=2024-06-01-preview" `
        --query primaryKey -o tsv
}

Write-Host "APIM_GATEWAY_URL      = $gatewayUrl"
Write-Host "APIM_SUBSCRIPTION_KEY = $key"
Write-Host ""
Write-Host "Despliegue de chat    = $($out.chatDeployment.value)"
Write-Host "Despliegue embeddings = $($out.embeddingsDeployment.value)"
Write-Host "Application Insights  = $($out.appInsightsName.value)"
Write-Host ""
Write-Host "Para PowerShell:" -ForegroundColor Cyan
Write-Host "  `$env:APIM_GATEWAY_URL=`"$gatewayUrl`""
Write-Host "  `$env:APIM_SUBSCRIPTION_KEY=`"$key`""
