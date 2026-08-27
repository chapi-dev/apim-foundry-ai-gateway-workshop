# Aplica el workshop sobre un APIM YA EXISTENTE (modo reutilización).
# No crea APIM ni monitorización: reutiliza los tuyos para ahorrar coste.
#
# Requisitos: edita infra/main.reuse.bicepparam con tu APIM, su principalId de MI,
# el logger de App Insights y los nombres de las cuentas de Foundry a usar como backends.
param(
    [string]$FoundryResourceGroup = "rg-apim-workshop"  # RG donde viven las cuentas de Foundry
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $PSScriptRoot

Write-Host "Aplicando la API del AI Gateway sobre el APIM existente..." -ForegroundColor Yellow
az deployment group create `
    --resource-group $FoundryResourceGroup `
    --name aigw-reuse `
    --template-file "$here\infra\main.reuse.bicep" `
    --parameters "$here\infra\main.reuse.bicepparam"

Write-Host "Hecho. Usa scripts\get-keys.ps1 -ApimName <apim> -ResourceGroup <rg-del-apim>" -ForegroundColor Green
