# Configura el SKU AI Gateway (preview) de punta a punta: proveedores Foundry, modelos,
# servidor MCP, políticas de gobierno y exportador de telemetría. Es idempotente, así que se
# puede relanzar sin miedo.
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
    [string]$AppInsightsResourceGroup = "rg-aigateway-dev-01",
    # Techos de las políticas de gobierno que se aplican a cada asset.
    [int]$TokensPerMinute = 10000,
    [int]$CallsPerMinute = 100,
    # Guarda el prompt y la respuesta completos en las trazas. Útil para depurar, pero manda
    # datos de usuario a Log Analytics: apagado por defecto.
    [switch]$CapturePayloads,
    [switch]$SkipTelemetry,
    [switch]$SkipPolicies
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

# El exportador se configura en modo OpenTelemetry (OTLP). Es el único que alimenta la tabla
# OTelSpans de Log Analytics, que es de donde lee el panel Monitoring del portal del gateway.
# El exportador clásico "ApplicationInsights" sólo manda métricas y deja el panel vacío.
if ($SkipTelemetry) {
    Write-Host "  Telemetria omitida (-SkipTelemetry)." -ForegroundColor Yellow
} elseif (-not $AppInsightsName) {
    Write-Host "  Telemetria omitida (-AppInsightsName vacio)." -ForegroundColor Yellow
} else {
    $aiId = "/subscriptions/$sub/resourceGroups/$AppInsightsResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName"
    $aiUrl = "https://management.azure.com$aiId"
    # La ingesta OTLP se pide con una api-version propia del recurso de App Insights.
    $aiApiVersion = "2020-02-02-preview"

    function Get-AppInsights {
        $r = Invoke-WebRequest -Uri "$aiUrl`?api-version=$aiApiVersion" -Headers $headers -SkipHttpErrorCheck
        if ([int]$r.StatusCode -ge 300) { return $null }
        ($r.Content | ConvertFrom-Json).properties
    }

    $props = Get-AppInsights
    if (-not $props) {
        Write-Host "  No se encontro el Application Insights '$AppInsightsName'; telemetria omitida." -ForegroundColor Yellow
    } else {
        # 5.1 Activar la ingesta OTLP. Azure aprovisiona por detrás un DCE y un DCR gestionados
        #     en un grupo de recursos ai_<nombre>_<appId>_managed y publica los tres endpoints.
        if ($props.AzureMonitorWorkspaceIngestionMode -ne "Enabled") {
            $enable = Invoke-WebRequest -Uri "$aiUrl`?api-version=$aiApiVersion" -Method Patch -Headers $headers `
                -Body (@{ properties = @{ AzureMonitorWorkspaceIngestionMode = "Enabled" } } | ConvertTo-Json) -SkipHttpErrorCheck
            Write-Result ([int]$enable.StatusCode) "ingesta OTLP activada en $AppInsightsName"
        } else {
            Write-Host "  [200] ingesta OTLP ya activa en $AppInsightsName" -ForegroundColor Green
        }

        # 5.2 Los endpoints tardan un poco en aparecer; el asistente del portal espera lo mismo.
        $deadline = (Get-Date).AddSeconds(180)
        while ((Get-Date) -lt $deadline -and -not ($props.OTLPMetricsEndpoint -and $props.OTLPLogsEndpoint -and $props.OTLPTracesEndpoint)) {
            Start-Sleep -Seconds 5
            $props = Get-AppInsights
        }

        if (-not ($props.OTLPMetricsEndpoint -and $props.OTLPLogsEndpoint -and $props.OTLPTracesEndpoint)) {
            Write-Host "  Los endpoints OTLP no se aprovisionaron a tiempo; reintenta el script en unos minutos." -ForegroundColor Yellow
        } else {
            Write-Host "  [200] endpoints OTLP disponibles (metrics, logs, traces)" -ForegroundColor Green

            # 5.3 El gateway escribe en el DCR gestionado con su identidad, así que necesita el
            #     rol Monitoring Metrics Publisher sobre él. Sin esto la ingesta falla en silencio.
            $principalId = (Invoke-Arm -Path $service).Content.identity.principalId
            $managedRg = "ai_$($AppInsightsName)_$($props.AppId)_managed"
            $dcrId = "/subscriptions/$sub/resourceGroups/$managedRg/providers/Microsoft.Insights/dataCollectionRules/managed-$AppInsightsName-dcr"
            if (-not $principalId) {
                Write-Host "  El gateway no tiene identidad administrada; no se puede asignar el rol sobre el DCR." -ForegroundColor Yellow
            } else {
                $existing = az role assignment list --scope $dcrId --assignee $principalId `
                    --query "[?roleDefinitionName=='Monitoring Metrics Publisher'] | length(@)" -o tsv 2>$null
                if ($existing -eq "0" -or -not $existing) {
                    az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
                        --role "Monitoring Metrics Publisher" --scope $dcrId -o none 2>$null
                    Write-Host "  [200] rol Monitoring Metrics Publisher sobre el DCR gestionado" -ForegroundColor Green
                } else {
                    Write-Host "  [200] rol Monitoring Metrics Publisher ya asignado" -ForegroundColor Green
                }
            }

            # 5.4 El campo 'kind' es inmutable: si el exportador existe con otro tipo hay que
            #     borrarlo y volver a crearlo, no basta con un PUT.
            $current = Invoke-Arm -Path "$workspace/telemetryExporters/appinsights"
            if ($current.Status -lt 300 -and $current.Content.properties.kind -ne "OpenTelemetry") {
                Invoke-Arm -Path "$workspace/telemetryExporters/appinsights" -Method Delete | Out-Null
                Start-Sleep -Seconds 3
                $current = @{ Status = 404 }
            }

            if ($current.Status -ge 300) {
                $telemetry = Invoke-Arm -Path "$workspace/telemetryExporters/appinsights" -Method Put -Body @{
                    properties = @{
                        kind                = "OpenTelemetry"
                        payloadCapture      = [bool]$CapturePayloads
                        applicationInsights = @{ resourceId = $aiId }
                        openTelemetry       = @{
                            metricsEndpoint = $props.OTLPMetricsEndpoint
                            logsEndpoint    = $props.OTLPLogsEndpoint
                            tracesEndpoint  = $props.OTLPTracesEndpoint
                            credentials     = @{ managedIdentity = @{ resource = "https://monitor.azure.com" } }
                        }
                    }
                }
                Write-Result $telemetry.Status "exportador OpenTelemetry creado -> $AppInsightsName"
                if ($telemetry.Status -ge 300) { Write-Host "     $($telemetry.Raw)" -ForegroundColor DarkGray }
            } else {
                # Ya existe: se actualiza con PATCH campo a campo, igual que hace el portal. Un PUT
                # completo choca con las credenciales que el servicio normaliza al crear el recurso.
                $telemetry = Invoke-Arm -Path "$workspace/telemetryExporters/appinsights" -Method Patch -Body @{
                    properties = @{
                        payloadCapture = [bool]$CapturePayloads
                        openTelemetry  = @{
                            metricsEndpoint = $props.OTLPMetricsEndpoint
                            logsEndpoint    = $props.OTLPLogsEndpoint
                            tracesEndpoint  = $props.OTLPTracesEndpoint
                        }
                    }
                }
                Write-Result $telemetry.Status "exportador OpenTelemetry actualizado -> $AppInsightsName"
                if ($telemetry.Status -ge 300) { Write-Host "     $($telemetry.Raw)" -ForegroundColor DarkGray }
            }

            # 5.5 El exportador nace con metrics y tracing apagados. El PATCH de 'tracing' sólo
            #     se acepta si el mismo cuerpo repite 'kind'; si no, responde 400.
            $signals = Invoke-Arm -Path "$workspace/telemetryExporters/appinsights" -Method Patch -Body @{
                properties = @{ kind = "OpenTelemetry"; metrics = $true; tracing = $true }
            }
            Write-Result $signals.Status "senales activadas (metrics + tracing)"
            if ($signals.Status -ge 300) { Write-Host "     $($signals.Raw)" -ForegroundColor DarkGray }
        }
    }
}

# --------------------------------------------------------------------------------------------
Write-Step "6. Politicas de gobierno"

# Las políticas no son un recurso propio: viajan dentro del modelo o del toolserver, en
# properties.policies, y se aplican con PATCH (el PUT completo choca con la inmutabilidad
# del asset). Es la misma llamada que hace el asistente del portal.
# Tipos admitidos: tokenLimit, costLimit, requestRateLimit, contentSafety, fallback,
# ipFilter y cors.
if ($SkipPolicies) {
    Write-Host "  Politicas omitidas (-SkipPolicies)." -ForegroundColor Yellow
} else {
    $tokenLimit = @{ type = "tokenLimit"; count = $TokensPerMinute; period = "minute"; counterKey = "IPAddress" }
    $rateLimit = @{ type = "requestRateLimit"; callsPerPeriod = $CallsPerMinute; periodSeconds = 60; counterKey = "IPAddress" }
    # El gateway bloquea a partir de la severidad indicada. Medium es el punto de equilibrio.
    $contentSafety = @{
        type            = "contentSafety"
        hateSeverity    = "Medium"
        violenceSeverity = "Medium"
        sexualSeverity  = "Medium"
        selfHarmSeverity = "Medium"
    }

    $providers = Invoke-Arm -Path "$workspace/modelProviders"
    foreach ($provider in $providers.Content.value) {
        $models = Invoke-Arm -Path "$workspace/modelProviders/$($provider.name)/models"
        foreach ($model in $models.Content.value) {
            # Los embeddings no pasan por Content Safety: se limitan por número de llamadas.
            # Ojo: un 'if' usado como expresión desenvuelve los arrays de un solo elemento,
            # y la API entonces recibe un objeto en vez de una lista.
            $policies = @($tokenLimit, $contentSafety)
            if ($model.properties.supportedEndpoints -contains "/embeddings") {
                $policies = @($rateLimit)
            }
            $applied = Invoke-Arm -Path "$workspace/modelProviders/$($provider.name)/models/$($model.name)" `
                -Method Patch -Body @{ properties = @{ policies = $policies } }
            Write-Result $applied.Status "modelo '$($model.name)' -> $(($policies.type) -join ', ')"
            if ($applied.Status -ge 300) { Write-Host "     $($applied.Raw)" -ForegroundColor DarkGray }
        }
    }

    $servers = Invoke-Arm -Path "$workspace/toolservers"
    foreach ($server in $servers.Content.value) {
        # El control plane devuelve de vez en cuando un 404 "Api not found" pasajero sobre
        # los toolservers; con un segundo intento se resuelve.
        $applied = Invoke-Arm -Path "$workspace/toolservers/$($server.name)" `
            -Method Patch -Body @{ properties = @{ policies = @($rateLimit) } }
        if ($applied.Status -eq 404) {
            Start-Sleep -Seconds 3
            $applied = Invoke-Arm -Path "$workspace/toolservers/$($server.name)" `
                -Method Patch -Body @{ properties = @{ policies = @($rateLimit) } }
        }
        Write-Result $applied.Status "toolserver '$($server.name)' -> requestRateLimit"
        if ($applied.Status -ge 300) { Write-Host "     $($applied.Raw)" -ForegroundColor DarkGray }
    }
}

# --------------------------------------------------------------------------------------------
Write-Step "Resumen"

foreach ($asset in @("modelProviders", "models", "toolservers", "telemetryExporters")) {
    $list = Invoke-Arm -Path "$workspace/$asset"
    $names = @($list.Content.value | ForEach-Object { $_.name })
    Write-Host ("{0,-20} {1}" -f $asset, $(if ($names) { $names -join ", " } else { "(vacio)" }))
}

$total = 0
$all = Invoke-Arm -Path "$workspace/models"
foreach ($model in $all.Content.value) { $total += @($model.properties.policies).Count }
$servers = Invoke-Arm -Path "$workspace/toolservers"
foreach ($server in $servers.Content.value) { $total += @($server.properties.policies).Count }
Write-Host ("{0,-20} {1}" -f "politicas", $total)

Write-Host "`nSiguiente paso: ./aigw-test.ps1 -GatewayName $GatewayName -GatewayResourceGroup $GatewayResourceGroup" -ForegroundColor Cyan
