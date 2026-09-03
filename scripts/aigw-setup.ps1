# Configura el SKU AI Gateway (preview) de punta a punta: proveedores Foundry, modelos,
# servidor MCP y exportador de telemetría. Es idempotente (todo son PUT), así que se puede
# relanzar sin miedo.
#
#   ./aigw-setup.ps1 -GatewayName dev-testing-apim-preview -GatewayResourceGroup ai-gateway-dev-testing-apim-preview
#
# Requisitos previos (ver labs/13-ai-gateway-tier.md):
#   - Feature flag Microsoft.ApiManagement/AIGatewayPreview registrado
#   - El gateway con identidad administrada y rol "Foundry User" sobre cada cuenta de Foundry
param(
    [Parameter(Mandatory = $true)][string]$GatewayName,
    [Parameter(Mandatory = $true)][string]$GatewayResourceGroup,
    [string]$FoundryResourceGroup = "rg-apim-workshop",
    [string[]]$FoundryAccounts = @("aigwqyxvxaoai1", "aigwqyxvxaoai2"),
    [string]$McpUrl = "https://learn.microsoft.com/api/mcp",
    # Application Insights al que mandar la métrica de tokens. Vacío = no configurar telemetría.
    [string]$AppInsightsName = "appi-aigw-dev-01",
    [string]$AppInsightsResourceGroup = "rg-aigateway-dev-01"
)

$ErrorActionPreference = "Stop"

# La única api-version que responde hoy. La 2026-05-01-preview que cita la documentación
# todavía no está desplegada en las regiones de preview.
$apiVersion = "2025-09-01-preview"

$sub = az account show --query id -o tsv
$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

$serviceId = "/subscriptions/$sub/resourceGroups/$GatewayResourceGroup/providers/Microsoft.ApiManagement/service/$GatewayName"
$service = "https://management.azure.com$serviceId"
# Los assets del AI Gateway no cuelgan del servicio sino de un workspace fijo llamado "default".
$workspace = "$service/workspaces/default"

function Invoke-Arm {
    param([string]$Path, [string]$Method = "Get", $Body)
    $uri = "$Path`?api-version=$apiVersion"
    $args = @{ Uri = $uri; Method = $Method; Headers = $headers; SkipHttpErrorCheck = $true }
    if ($Body) { $args.Body = ($Body | ConvertTo-Json -Depth 12) }
    $response = Invoke-WebRequest @args
    $content = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
    [pscustomobject]@{ Status = [int]$response.StatusCode; Content = $content; Raw = $response.Content }
}

function Write-Step { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

function Write-Result {
    param([int]$Status, [string]$What)
    if ($Status -ge 200 -and $Status -lt 300) {
        Write-Host ("  [{0}] {1}" -f $Status, $What) -ForegroundColor Green
    } else {
        Write-Host ("  [{0}] {1}" -f $Status, $What) -ForegroundColor Red
    }
}

Write-Host "Gateway : $GatewayName ($GatewayResourceGroup)"
Write-Host "Foundry : $($FoundryAccounts -join ', ') ($FoundryResourceGroup)"

# --------------------------------------------------------------------------------------------
Write-Step "1. Comprobaciones previas"

$state = az feature show --namespace Microsoft.ApiManagement --name AIGatewayPreview --query properties.state -o tsv 2>$null
if ($state -ne "Registered") {
    Write-Host "  Feature flag AIGatewayPreview = $state" -ForegroundColor Red
    Write-Host "  Registra con: az feature register --namespace Microsoft.ApiManagement --name AIGatewayPreview" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Feature flag AIGatewayPreview = Registered" -ForegroundColor Green

$principalId = az resource show --ids $serviceId --query identity.principalId -o tsv 2>$null
if (-not $principalId) {
    Write-Host "  El gateway no tiene identidad administrada. Actívala en 'Managed identities'." -ForegroundColor Red
    exit 1
}
Write-Host "  Identidad administrada = $principalId" -ForegroundColor Green

# --------------------------------------------------------------------------------------------
Write-Step "2. Rol 'Foundry User' sobre cada Foundry (acceso keyless)"

# Rol integrado Foundry User. Se referencia por ID, no por nombre, como recomienda la doc.
$foundryUserRole = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
foreach ($account in $FoundryAccounts) {
    $scope = "/subscriptions/$sub/resourceGroups/$FoundryResourceGroup/providers/Microsoft.CognitiveServices/accounts/$account"
    $existing = az role assignment list --assignee-object-id $principalId --scope $scope --query "[?roleDefinitionId!=null].roleDefinitionName" -o tsv 2>$null
    if ($existing -match "Foundry User|Azure AI User|Cognitive Services User") {
        Write-Host "  $account : ya asignado" -ForegroundColor Green
    } else {
        az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
            --role $foundryUserRole --scope $scope -o none 2>$null
        Write-Host "  $account : rol asignado (la propagacion tarda unos minutos)" -ForegroundColor Yellow
    }
}

# --------------------------------------------------------------------------------------------
Write-Step "3. Proveedores de modelos y modelos"

# El gateway enruta por coincidencia EXACTA de deployment.modelName, y ese nombre debe ser
# único en todo el workspace. Además los modelos son inmutables: un PUT sobre uno que ya
# existe choca con su propia comprobación de unicidad, así que hay que saltarse los que ya
# están y borrarlos a mano si se quiere cambiarlos.
$registered = @{}
$existing = Invoke-Arm -Path "$workspace/models"
foreach ($current in $existing.Content.value) {
    $registered[$current.properties.deployment.modelName] = "ya registrado"
}
$index = 0

foreach ($account in $FoundryAccounts) {
    $index++
    $providerName = "foundry$index"
    $resourceId = "/subscriptions/$sub/resourceGroups/$FoundryResourceGroup/providers/Microsoft.CognitiveServices/accounts/$account"

    # El endpoint tiene que ser el de "AI Foundry API". Si se omite, los modelos fallan
    # después con "Parent provider ... has no projected backend".
    $endpoint = az cognitiveservices account show -n $account -g $FoundryResourceGroup `
        --query "properties.endpoints.\"AI Foundry API\"" -o tsv 2>$null
    if (-not $endpoint) { $endpoint = "https://$account.services.ai.azure.com/" }

    $provider = Invoke-Arm -Path "$workspace/modelProviders/$providerName" -Method Put -Body @{
        properties = @{
            kind        = "Foundry"
            displayName = $account
            foundry     = @{
                endpoint       = $endpoint
                resourceIds    = @($resourceId)
                authentication = @{ kind = "ManagedIdentity" }
            }
        }
    }
    Write-Result $provider.Status "proveedor $providerName -> $account"
    if ($provider.Status -ge 300) { Write-Host "     $($provider.Raw)" -ForegroundColor DarkGray; continue }

    $deployments = az cognitiveservices account deployment list -n $account -g $FoundryResourceGroup -o json | ConvertFrom-Json
    foreach ($deployment in $deployments) {
        $deploymentName = $deployment.name
        if ($registered.ContainsKey($deploymentName)) {
            Write-Host "  [--] '$deploymentName' omitido: $($registered[$deploymentName])" -ForegroundColor Yellow
            continue
        }

        # Los embeddings se sirven en /embeddings; el resto, en /chat/completions.
        $isEmbedding = $deployment.properties.model.name -match "embedding"
        $supported = if ($isEmbedding) { @("/embeddings") } else { @("/chat/completions") }

        $model = Invoke-Arm -Path "$workspace/modelProviders/$providerName/models/$deploymentName" -Method Put -Body @{
            properties = @{
                displayName        = "$($deployment.properties.model.name) ($account)"
                supportedEndpoints = $supported
                deployment         = @{ modelName = $deploymentName; resourceId = $resourceId }
            }
        }
        Write-Result $model.Status "modelo '$deploymentName' -> $($deployment.properties.model.name)  [$($supported -join ',')]"
        if ($model.Status -lt 300) { $registered[$deploymentName] = "registrado en $account" }
        else { Write-Host "     $($model.Raw)" -ForegroundColor DarkGray }
    }
}

# --------------------------------------------------------------------------------------------
Write-Step "4. Servidor MCP"

# Igual que los modelos, un toolserver existente no se puede actualizar: el PUT devuelve
# 404 "Api not found". Para cambiarlo hay que borrarlo y volver a crearlo.
$toolservers = Invoke-Arm -Path "$workspace/toolservers"
if ($toolservers.Content.value | Where-Object { $_.name -eq "learn" }) {
    Write-Host "  [--] toolserver 'learn' ya existe (borralo si quieres recrearlo)" -ForegroundColor Yellow
} else {
    $mcp = Invoke-Arm -Path "$workspace/toolservers/learn" -Method Put -Body @{
        properties = @{
            displayName = "Microsoft Learn"
            description = "Documentacion oficial de Microsoft expuesta como herramientas MCP"
            type        = "Mcp"
            endpoints   = @(@{
                    name           = "learn"
                    kind           = "Mcp"
                    mcp            = @{ url = $McpUrl }
                    authentication = @{ kind = "None" }
                })
        }
    }
    Write-Result $mcp.Status "toolserver 'learn' -> $McpUrl"
    if ($mcp.Status -ge 300) { Write-Host "     $($mcp.Raw)" -ForegroundColor DarkGray }
}

# --------------------------------------------------------------------------------------------
Write-Step "5. Telemetria"

if ($AppInsightsName) {
    $aiId = "/subscriptions/$sub/resourceGroups/$AppInsightsResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName"
    $connectionString = az resource show --ids $aiId --query "properties.ConnectionString" -o tsv 2>$null
    if ($connectionString) {
        # 'tracing' solo se admite en exportadores OpenTelemetry; con App Insights hay que
        # dejarlo apagado o la API responde 400.
        $telemetry = Invoke-Arm -Path "$workspace/telemetryExporters/appinsights" -Method Put -Body @{
            properties = @{
                displayName          = "App Insights"
                kind                 = "ApplicationInsights"
                metrics              = $true
                applicationInsights  = @{ connectionString = $connectionString; resourceId = $aiId }
            }
        }
        Write-Result $telemetry.Status "exportador de metricas -> $AppInsightsName"
    } else {
        Write-Host "  No se encontro el Application Insights '$AppInsightsName'; telemetria omitida." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Telemetria omitida (-AppInsightsName vacio)." -ForegroundColor Yellow
}

# --------------------------------------------------------------------------------------------
Write-Step "Resumen"

foreach ($asset in @("modelProviders", "models", "toolservers", "telemetryExporters")) {
    $list = Invoke-Arm -Path "$workspace/$asset"
    $names = @($list.Content.value | ForEach-Object { $_.name })
    "{0,-20} {1}" -f $asset, $(if ($names) { $names -join ", " } else { "(vacio)" })
}

Write-Host "`nLas politicas se configuran en el portal: no tienen API de gestion todavia." -ForegroundColor Yellow
Write-Host "Siguiente paso: ./aigw-test.ps1 -GatewayName $GatewayName -GatewayResourceGroup $GatewayResourceGroup" -ForegroundColor Cyan
