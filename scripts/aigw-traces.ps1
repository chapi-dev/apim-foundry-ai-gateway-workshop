# Consulta las trazas distribuidas que el AI Gateway (preview) manda por OTLP a Log Analytics.
#
#   ./aigw-traces.ps1
#   ./aigw-traces.ps1 -Hours 24 -Trace <TraceId>
#
# Mientras aigw-metrics.ps1 responde "cuanto se ha consumido", este script responde "que ha
# pasado dentro del gateway en cada peticion": el gateway emite un span por cada fase y por
# cada politica evaluada, asi que la traza demuestra el gobierno aplicado sin abrir el portal.
#
# Requiere el exportador en modo OpenTelemetry con tracing activo (./aigw-setup.ps1 paso 5).
# Los datos van a la tabla OTelSpans del workspace de Log Analytics, no a Application Insights,
# asi que aqui se usa la API de Log Analytics y no la de App Insights.
param(
    [string]$AppInsightsName = "appi-aigw-dev-01",
    [string]$ResourceGroup = "rg-aigateway-dev-01",
    [int]$Hours = 3,
    # TraceId concreto a desglosar. Por defecto se desglosa la ultima peticion recibida.
    [string]$Trace
)

$ErrorActionPreference = "Stop"

$sub = az account show --query id -o tsv
$componentId = "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName"
$workspaceId = az resource show --ids $componentId --query "properties.WorkspaceResourceId" -o tsv 2>$null
if (-not $workspaceId) {
    Write-Host "No se encontro el Application Insights '$AppInsightsName' o no es workspace-based." -ForegroundColor Red
    exit 1
}
# La API de consulta no usa el resource id del workspace sino su GUID (customerId).
$customerId = az resource show --ids $workspaceId --query "properties.customerId" -o tsv

$token = az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

function Invoke-Kql {
    param([string]$Query)
    $body = @{ query = $Query } | ConvertTo-Json
    $response = Invoke-WebRequest -Uri "https://api.loganalytics.io/v1/workspaces/$customerId/query" `
        -Method Post -Headers $headers -Body $body -SkipHttpErrorCheck
    $content = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    if ([int]$response.StatusCode -ne 200) {
        Write-Host "  Error [$($response.StatusCode)]: $content" -ForegroundColor Red
        return $null
    }
    $table = ($content | ConvertFrom-Json).tables[0]
    if (-not $table.rows) { return @() }
    # Con una sola columna la propiedad no llega como array y el indexado devolveria caracteres.
    $columns = @($table.columns.name)
    $table.rows | ForEach-Object {
        $row = $_
        $object = [ordered]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) { $object[$columns[$i]] = $row[$i] }
        [pscustomobject]$object
    }
}

function Write-Step { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

Write-Host "Log Analytics : $(Split-Path $workspaceId -Leaf) ($ResourceGroup)"
Write-Host "Ventana       : ultimas $Hours h"

# --------------------------------------------------------------------------------------------
Write-Step "Peticiones atendidas"

# Los spans raiz (sin padre) son una peticion completa de extremo a extremo. http.route separa
# las llamadas a modelos de las llamadas al servidor MCP.
$requests = Invoke-Kql @"
OTelSpans
| where TimeGenerated > ago(${Hours}h) and isempty(ParentSpanId)
| extend ruta    = tostring(Attributes["http.route"]),
         modelo  = tostring(Attributes["azure.apim.api.name"]),
         codigo  = tostring(Attributes["http.response.status_code"]),
         desenlace = tostring(Attributes["azure.apim.outcome"])
| summarize peticiones = count(), ["p95 ms"] = round(percentile(DurationMs, 95)) by ruta, modelo, codigo, desenlace
| order by peticiones desc
"@

if (-not $requests) {
    Write-Host "  Sin trazas. Comprueba el exportador y genera trafico:" -ForegroundColor Yellow
    Write-Host "  ./aigw-setup.ps1  (paso 5 deja el exportador en modo OpenTelemetry con tracing)" -ForegroundColor DarkGray
    Write-Host "  ./aigw-test.ps1   (genera trafico)" -ForegroundColor DarkGray
    Write-Host "  La ingesta tarda unos minutos en aparecer." -ForegroundColor DarkGray
    exit 0
}
$requests | Format-Table -AutoSize

# --------------------------------------------------------------------------------------------
Write-Step "Politicas evaluadas"

# Cada politica de gobierno deja su propio span. Esta tabla es la prueba de que el gateway
# evalua los limites de tokens, el content safety y el resto en cada peticion.
Invoke-Kql @"
OTelSpans
| where TimeGenerated > ago(${Hours}h) and Name startswith "policy "
| extend politica = tostring(Attributes["azure.apim.policy.type"]),
         seccion  = tostring(Attributes["azure.apim.policy.section"]),
         ambito   = tostring(Attributes["azure.apim.policy.scope"]),
         desenlace = tostring(Attributes["azure.apim.outcome"])
| summarize veces = count(), ["media ms"] = round(avg(DurationMs), 3) by politica, seccion, ambito, desenlace
| order by veces desc
"@ | Format-Table -AutoSize

# --------------------------------------------------------------------------------------------
Write-Step "Peticiones rechazadas por el gobierno"

# Cuando una politica corta la peticion (429 por limite de tokens, 403 por content safety),
# el span raiz deja de ser 'success'. Aqui se ve quien corto y por que.
$blocked = Invoke-Kql @"
OTelSpans
| where TimeGenerated > ago(${Hours}h) and isempty(ParentSpanId)
| extend codigo = toint(Attributes["http.response.status_code"]),
         desenlace = tostring(Attributes["azure.apim.outcome"])
| where codigo >= 400
| join kind=leftouter (
    OTelSpans
    | where TimeGenerated > ago(${Hours}h) and Name startswith "policy "
    | where tostring(Attributes["azure.apim.outcome"]) != "success"
    | project TraceId, corto = tostring(Attributes["azure.apim.policy.type"])
) on TraceId
| summarize veces = count() by codigo, desenlace, corto = coalesce(corto, "(sin politica)")
| order by veces desc
"@
if ($blocked) { $blocked | Format-Table -AutoSize } else { Write-Host "  Ninguna. Prueba ./aigw-policies-test.ps1 -Demo para forzar un 429." -ForegroundColor DarkGray }

# --------------------------------------------------------------------------------------------
Write-Step "Detalle de una peticion"

if (-not $Trace) {
    $Trace = (Invoke-Kql @"
OTelSpans
| where TimeGenerated > ago(${Hours}h) and isempty(ParentSpanId)
| top 1 by TimeGenerated desc
| project TraceId
"@).TraceId
}

if (-not $Trace) {
    Write-Host "  Sin trazas que desglosar." -ForegroundColor DarkGray
} else {
    Write-Host "TraceId: $Trace`n"
    # El arbol se reconstruye enlazando cada span con su padre; la sangria hace visible que las
    # politicas cuelgan de 'inbound' u 'outbound' y la llamada real del modelo de 'backend'.
    $spans = Invoke-Kql @"
OTelSpans
| where TimeGenerated > ago(${Hours}h) and TraceId == "$Trace"
| project Name, SpanId, ParentSpanId, DurationMs, TimeGenerated,
          desenlace = tostring(Attributes["azure.apim.outcome"])
| order by TimeGenerated asc
"@
    $byParent = @{}
    foreach ($span in $spans) {
        $key = if ($span.ParentSpanId) { $span.ParentSpanId } else { "" }
        if (-not $byParent.ContainsKey($key)) { $byParent[$key] = @() }
        $byParent[$key] += $span
    }
    function Show-Span {
        param($Parent, [int]$Depth)
        foreach ($span in $byParent[$Parent]) {
            $color = if ($span.desenlace -eq "success") { "Gray" } else { "Yellow" }
            Write-Host ("{0}{1,-42} {2,10:N2} ms  {3}" -f ("  " * $Depth), $span.Name, $span.DurationMs, $span.desenlace) -ForegroundColor $color
            if ($byParent.ContainsKey($span.SpanId)) { Show-Span -Parent $span.SpanId -Depth ($Depth + 1) }
        }
    }
    Show-Span -Parent "" -Depth 0
}

Write-Host "`nEl mismo arbol se ve en el portal del gateway:" -ForegroundColor Cyan
Write-Host "  https://ai.gateway.azure.com > Monitoring > Traces" -ForegroundColor DarkGray
Write-Host "Y en el portal de Azure, con KQL sobre el workspace:" -ForegroundColor Cyan
Write-Host "  OTelSpans | where TimeGenerated > ago(1h) | order by TimeGenerated desc" -ForegroundColor DarkGray
