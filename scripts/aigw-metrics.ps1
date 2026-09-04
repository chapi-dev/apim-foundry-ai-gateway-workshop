# Consulta la telemetría que el AI Gateway (preview) manda a Application Insights.
#
#   ./aigw-metrics.ps1
#   ./aigw-metrics.ps1 -Hours 24
#
# El gateway emite una métrica OpenTelemetry de uso de tokens. La documentación la nombra
# 'gen_ai_client_token_usage' porque así se ve desde PromQL; dentro de Application Insights
# la métrica se llama 'azure.ai_gateway.client.token.usage' y se consulta con KQL sobre la
# tabla customMetrics.
#
# Se usa la API REST de Application Insights en vez de 'az monitor app-insights' para no
# depender de la extensión de CLI.
param(
    [string]$AppInsightsName = "appi-aigw-dev-01",
    [string]$ResourceGroup = "rg-aigateway-dev-01",
    [int]$Hours = 3
)

$ErrorActionPreference = "Stop"

$sub = az account show --query id -o tsv
$appId = az resource show --ids "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName" --query "properties.AppId" -o tsv
if (-not $appId) { Write-Host "No se encontro el Application Insights '$AppInsightsName'." -ForegroundColor Red; exit 1 }

$token = az account get-access-token --resource https://api.applicationinsights.io --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

function Invoke-Kql {
    param([string]$Query)
    $uri = "https://api.applicationinsights.io/v1/apps/$appId/query?query=$([uri]::EscapeDataString($Query))"
    $response = Invoke-WebRequest -Uri $uri -Headers $headers -SkipHttpErrorCheck
    if ([int]$response.StatusCode -ne 200) {
        Write-Host "  Error [$($response.StatusCode)]: $($response.Content)" -ForegroundColor Red
        return $null
    }
    $table = ($response.Content | ConvertFrom-Json).tables[0]
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

Write-Host "Application Insights : $AppInsightsName ($ResourceGroup)"
Write-Host "Ventana              : ultimas $Hours h"

# --------------------------------------------------------------------------------------------
Write-Step "Metricas recibidas"

$metrics = Invoke-Kql "customMetrics | where timestamp > ago(${Hours}h) | summarize muestras=count(), ultima=max(timestamp) by name | order by muestras desc"
if (-not $metrics) {
    Write-Host "  Sin datos. Comprueba que el exportador existe y que 'metrics' esta a true:" -ForegroundColor Yellow
    Write-Host "  Portal > AI Gateway > Monitoring, o ./aigw-setup.ps1" -ForegroundColor DarkGray
    Write-Host "  La telemetria tarda unos minutos en aparecer tras generar trafico." -ForegroundColor DarkGray
    exit 0
}
$metrics | Format-Table -AutoSize

if (-not ($metrics.name -contains "azure.ai_gateway.client.token.usage")) {
    Write-Host "  Aun no ha llegado 'azure.ai_gateway.client.token.usage'." -ForegroundColor Yellow
    Write-Host "  Genera trafico con ./aigw-test.ps1 y vuelve a intentarlo en unos minutos." -ForegroundColor DarkGray
    exit 0
}

# --------------------------------------------------------------------------------------------
Write-Step "Tokens por modelo"

# gen_ai.request.model es lo que pidio el cliente (el nombre del despliegue) y
# gen_ai.response.model el modelo real que respondio: comparar ambos deja ver el enrutado.
Invoke-Kql @"
customMetrics
| where timestamp > ago(${Hours}h) and name == "azure.ai_gateway.client.token.usage"
| extend modelo    = tostring(customDimensions["gen_ai.request.model"]),
         backend   = tostring(customDimensions["gen_ai.response.model"]),
         tipo      = tostring(customDimensions["gen_ai.token.type"])
| where tipo in ("prompt_tokens", "completion_tokens", "total_tokens")
| summarize tokens = sum(valueSum) by modelo, backend, tipo
| evaluate pivot(tipo, sum(tokens))
| order by modelo asc
"@ | Format-Table -AutoSize

# --------------------------------------------------------------------------------------------
Write-Step "Consumo por clave de runtime"

# azure.ai_gateway.api_key_id permite atribuir el gasto a cada aplicacion, siempre que cada
# una tenga su propia clave (en preview las claves son de gateway, no por modelo).
Invoke-Kql @"
customMetrics
| where timestamp > ago(${Hours}h) and name == "azure.ai_gateway.client.token.usage"
| where tostring(customDimensions["gen_ai.token.type"]) == "total_tokens"
| extend clave = tostring(customDimensions["azure.ai_gateway.api_key_id"]),
         modelo = tostring(customDimensions["gen_ai.request.model"])
| summarize tokens = sum(valueSum), llamadas = sum(valueCount) by clave, modelo
| order by tokens desc
"@ | Format-Table -AutoSize

# --------------------------------------------------------------------------------------------
Write-Step "Coste estimado"

# Metrica extra que el gateway emite y que no aparece en la documentacion: el coste calculado
# a partir del consumo, con divisa propia. Sirve para orientarse; para facturar, Cost Management.
$cost = Invoke-Kql @"
customMetrics
| where timestamp > ago(${Hours}h) and name == "azure.ai_gateway.client.token.cost"
| extend modelo   = tostring(customDimensions["gen_ai.request.model"]),
         divisa   = tostring(customDimensions["azure.ai_gateway.currency"]),
         sinPrecio = tostring(customDimensions["azure.ai_gateway.price_missing"])
| summarize coste = sum(valueSum), sinTarifa = make_set(sinPrecio) by modelo, divisa
| project modelo, divisa, coste = tostring(round(coste, 8)), ["precio ausente"] = tostring(sinTarifa)
| order by modelo asc
"@
if ($cost) { $cost | Format-Table -AutoSize } else { Write-Host "  (sin datos de coste)" -ForegroundColor DarkGray }

# --------------------------------------------------------------------------------------------
Write-Step "Evolucion por minuto"

Invoke-Kql @"
customMetrics
| where timestamp > ago(${Hours}h) and name == "azure.ai_gateway.client.token.usage"
| where tostring(customDimensions["gen_ai.token.type"]) == "total_tokens"
| summarize tokens = sum(valueSum) by bin(timestamp, 1m)
| order by timestamp asc
"@ | Format-Table -AutoSize

Write-Host "El portal trae ademas un panel de consumo de tokens listo:" -ForegroundColor Cyan
Write-Host "  AI Gateway > Monitoring" -ForegroundColor DarkGray
Write-Host "Y desde PromQL la misma metrica se consulta asi:" -ForegroundColor Cyan
Write-Host "  sum by (gen_ai_request_model) (gen_ai_client_token_usage)" -ForegroundColor DarkGray
