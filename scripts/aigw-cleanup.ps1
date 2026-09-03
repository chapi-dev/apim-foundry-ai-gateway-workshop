# Vacía los assets del AI Gateway (preview): modelos, proveedores, servidores MCP y
# exportadores de telemetría. No borra el gateway ni los Foundry.
#
#   ./aigw-cleanup.ps1 -GatewayName dev-testing-apim-preview -GatewayResourceGroup ai-gateway-dev-testing-apim-preview
#   ./aigw-cleanup.ps1 ... -Only models
#
# Hace falta más de lo que parece: los modelos y los servidores MCP son inmutables (un PUT
# sobre uno existente falla), así que para cambiar cualquier cosa hay que borrar y recrear
# con ./aigw-setup.ps1.
param(
    [Parameter(Mandatory = $true)][string]$GatewayName,
    [Parameter(Mandatory = $true)][string]$GatewayResourceGroup,
    [ValidateSet("all", "models", "toolservers", "telemetry")]
    [string]$Only = "all",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$apiVersion = "2025-09-01-preview"

$sub = az account show --query id -o tsv
$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

$workspace = "https://management.azure.com/subscriptions/$sub/resourceGroups/$GatewayResourceGroup/providers/Microsoft.ApiManagement/service/$GatewayName/workspaces/default"

function Get-Assets {
    param([string]$Path)
    $response = Invoke-WebRequest -Uri "$workspace/$Path`?api-version=$apiVersion" -Headers $headers -SkipHttpErrorCheck
    if ([int]$response.StatusCode -ne 200) { return @() }
    @(($response.Content | ConvertFrom-Json).value)
}

function Remove-Asset {
    param([string]$Path, [string]$Label)
    $response = Invoke-WebRequest -Uri "$workspace/$Path`?api-version=$apiVersion" -Method Delete -Headers $headers -SkipHttpErrorCheck
    $status = [int]$response.StatusCode
    $color = if ($status -lt 300) { "Green" } else { "Red" }
    Write-Host ("  [{0}] {1}" -f $status, $Label) -ForegroundColor $color
}

Write-Host "Gateway : $GatewayName ($GatewayResourceGroup)"
Write-Host "Alcance : $Only"

if (-not $Force) {
    $answer = Read-Host "Esto borra los assets del gateway. Escribe 'si' para continuar"
    if ($answer -ne "si") { Write-Host "Cancelado."; exit 0 }
}

if ($Only -in @("all", "models")) {
    Write-Host "`n=== Modelos y proveedores ===" -ForegroundColor Cyan
    foreach ($provider in Get-Assets "modelProviders") {
        # Los modelos cuelgan del proveedor: hay que vaciarlo antes de borrarlo.
        foreach ($model in Get-Assets "modelProviders/$($provider.name)/models") {
            Remove-Asset "modelProviders/$($provider.name)/models/$($model.name)" "modelo $($provider.name)/$($model.name)"
        }
        Remove-Asset "modelProviders/$($provider.name)" "proveedor $($provider.name)"
    }
}

if ($Only -in @("all", "toolservers")) {
    Write-Host "`n=== Servidores MCP ===" -ForegroundColor Cyan
    foreach ($server in Get-Assets "toolservers") {
        Remove-Asset "toolservers/$($server.name)" "toolserver $($server.name)"
    }
}

if ($Only -in @("all", "telemetry")) {
    Write-Host "`n=== Telemetria ===" -ForegroundColor Cyan
    foreach ($exporter in Get-Assets "telemetryExporters") {
        Remove-Asset "telemetryExporters/$($exporter.name)" "exportador $($exporter.name)"
    }
}

Write-Host "`n=== Estado final ===" -ForegroundColor Cyan
foreach ($asset in @("modelProviders", "models", "toolservers", "telemetryExporters")) {
    $names = @(Get-Assets $asset | ForEach-Object { $_.name })
    "{0,-20} {1}" -f $asset, $(if ($names) { $names -join ", " } else { "(vacio)" })
}

Write-Host "`nLas politicas creadas en el portal no se tocan: bórralas desde Policies." -ForegroundColor Yellow
Write-Host "Para volver a montarlo todo: ./aigw-setup.ps1 -GatewayName $GatewayName -GatewayResourceGroup $GatewayResourceGroup" -ForegroundColor Cyan
