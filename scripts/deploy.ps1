# Despliega el núcleo del AI Gateway Workshop.
param(
    [string]$ResourceGroup = "rg-apim-workshop",
    [string]$Location = "swedencentral",
    [ValidateSet("Developer", "BasicV2", "StandardV2")]
    [string]$ApimSku = "Developer"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $PSScriptRoot

az group create -n $ResourceGroup -l $Location --tags workshop=apim-foundry-ai-gateway | Out-Null

Write-Host "Desplegando... (APIM Developer puede tardar ~40 min)" -ForegroundColor Yellow
az deployment group create `
    --resource-group $ResourceGroup `
    --name aigw-core `
    --template-file "$here\infra\main.bicep" `
    --parameters "$here\infra\main.bicepparam" `
    --parameters apimSku=$ApimSku location=$Location

Write-Host "Hecho. Ejecuta scripts\get-keys.ps1 para obtener el endpoint y la clave." -ForegroundColor Green
