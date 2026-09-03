# Prueba de humo del SKU AI Gateway (preview): recorre todas las superficies de runtime
# y deja claro qué funciona y qué no.
#
#   ./aigw-test.ps1 -GatewayName dev-testing-apim-preview -GatewayResourceGroup ai-gateway-dev-testing-apim-preview
#
# Lánzalo después de ./aigw-setup.ps1.
param(
    [Parameter(Mandatory = $true)][string]$GatewayName,
    [Parameter(Mandatory = $true)][string]$GatewayResourceGroup,
    # Si se indica, prueba solo ese modelo en vez de todos los registrados.
    [string]$Model
)

$ErrorActionPreference = "Stop"
$apiVersion = "2025-09-01-preview"

$sub = az account show --query id -o tsv
$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$arm = @{ Authorization = "Bearer $token" }

$service = "https://management.azure.com/subscriptions/$sub/resourceGroups/$GatewayResourceGroup/providers/Microsoft.ApiManagement/service/$GatewayName"
$workspace = "$service/workspaces/default"

# La clave de runtime cuelga del servicio, no del workspace, y se lee con listSecrets.
$key = (Invoke-RestMethod -Uri "$service/apikeys/master/listSecrets?api-version=$apiVersion" -Method Post -Headers $arm).primaryKey
$gateway = "https://$GatewayName.azure-api.net"

$results = @()
function Add-Result {
    param([string]$Test, [int]$Status, [bool]$Ok, [string]$Detail)
    $script:results += [pscustomobject]@{ Prueba = $Test; HTTP = $Status; OK = $(if ($Ok) { "si" } else { "NO" }); Detalle = $Detail }
    $color = if ($Ok) { "Green" } else { "Red" }
    Write-Host ("  [{0}] {1} - {2}" -f $Status, $Test, $Detail) -ForegroundColor $color
}

function Write-Step { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

Write-Host "Gateway : $gateway"
Write-Host "Clave   : $($key.Substring(0,6))... (leida de apikeys/master)"

# --------------------------------------------------------------------------------------------
Write-Step "Modelos registrados"

$models = (Invoke-RestMethod -Uri "$workspace/models?api-version=$apiVersion" -Headers $arm).value
if (-not $models) { Write-Host "  No hay modelos. Lanza primero ./aigw-setup.ps1" -ForegroundColor Red; exit 1 }
$models | ForEach-Object {
    "  {0,-14} {1,-24} {2}" -f $_.properties.deployment.modelName, $_.properties.displayName, ($_.properties.supportedEndpoints -join ",")
}

# OJO: el gateway enruta por deployment.modelName, no por el nombre del recurso ni por el
# nombre del modelo base. Mandar "gpt-4.1-mini" cuando el despliegue se llama "chat" da un
# 404 sin cuerpo, que es fácil de confundir con "la ruta no existe".
$chatModels = @($models | Where-Object { $_.properties.supportedEndpoints -contains "/chat/completions" } | ForEach-Object { $_.properties.deployment.modelName })
$embeddingModels = @($models | Where-Object { $_.properties.supportedEndpoints -contains "/embeddings" } | ForEach-Object { $_.properties.deployment.modelName })
if ($Model) {
    $chatModels = @($chatModels | Where-Object { $_ -eq $Model })
    $embeddingModels = @($embeddingModels | Where-Object { $_ -eq $Model })
}

# --------------------------------------------------------------------------------------------
Write-Step "1. Chat completions  (POST /default/models/openai/v1/chat/completions)"

foreach ($name in $chatModels) {
    $body = @{ model = $name; messages = @(@{ role = "user"; content = "Responde solo: OK" }); max_tokens = 10 } | ConvertTo-Json -Depth 5
    $response = Invoke-WebRequest -Uri "$gateway/default/models/openai/v1/chat/completions" -Method Post `
        -Headers @{ "api-key" = $key } -ContentType "application/json" -Body $body -SkipHttpErrorCheck -TimeoutSec 90
    $status = [int]$response.StatusCode
    if ($status -eq 200) {
        $payload = $response.Content | ConvertFrom-Json
        Add-Result "chat '$name'" $status $true "$($payload.usage.total_tokens) tokens, backend $($payload.model)"
    } else {
        $hint = if ($status -eq 404) { "404 = el valor de 'model' no coincide con ningun deployment.modelName" } else { $response.Content }
        Add-Result "chat '$name'" $status $false $hint
    }
    # Cabeceras de cuota: en el AI Gateway se llaman remaining-tokens / consumed-tokens
    # (en el APIM clásico son x-tokens-remaining / x-tokens-consumed).
    $remaining = $response.Headers["remaining-tokens"]
    if ($remaining) { Write-Host "       remaining-tokens: $remaining   consumed-tokens: $($response.Headers['consumed-tokens'])" -ForegroundColor DarkGray }
}

# --------------------------------------------------------------------------------------------
Write-Step "2. Embeddings  (POST /default/models/openai/v1/embeddings)"

foreach ($name in $embeddingModels) {
    $body = @{ model = $name; input = "gobierno de IA" } | ConvertTo-Json
    $response = Invoke-WebRequest -Uri "$gateway/default/models/openai/v1/embeddings" -Method Post `
        -Headers @{ "api-key" = $key } -ContentType "application/json" -Body $body -SkipHttpErrorCheck -TimeoutSec 90
    $status = [int]$response.StatusCode
    if ($status -eq 200) {
        $vector = ($response.Content | ConvertFrom-Json).data[0].embedding
        Add-Result "embeddings '$name'" $status $true "vector de $($vector.Count) dimensiones"
    } else {
        Add-Result "embeddings '$name'" $status $false $response.Content
    }
}
if (-not $embeddingModels) { Write-Host "  (ningun modelo de embeddings registrado)" -ForegroundColor DarkGray }

# --------------------------------------------------------------------------------------------
Write-Step "3. Superficie Anthropic  (POST /default/models/anthropic/v1/messages)"

# Esta ruta es PASSTHROUGH: el gateway conserva el formato nativo de Anthropic y lo reenvía
# tal cual al backend. Solo sirve para modelos Claude reales (proveedor Custom apuntando a
# api.anthropic.com o a un despliegue Claude en Foundry). NO traduce Anthropic -> OpenAI, así
# que un gpt-4.1-mini nunca responderá aquí: para eso está el puente del lab 12.
$anthropicModels = @($models | Where-Object { $_.properties.supportedEndpoints -match "messages" } | ForEach-Object { $_.properties.deployment.modelName })
if ($anthropicModels) {
    foreach ($name in $anthropicModels) {
        $body = @{ model = $name; max_tokens = 20; messages = @(@{ role = "user"; content = "Responde solo: OK" }) } | ConvertTo-Json -Depth 5
        $response = Invoke-WebRequest -Uri "$gateway/default/models/anthropic/v1/messages" -Method Post `
            -Headers @{ "api-key" = $key; "anthropic-version" = "2023-06-01" } `
            -ContentType "application/json" -Body $body -SkipHttpErrorCheck -TimeoutSec 90
        $status = [int]$response.StatusCode
        if ($status -eq 200) {
            $payload = $response.Content | ConvertFrom-Json
            Add-Result "anthropic '$name'" $status $true "content[0].text = '$($payload.content[0].text)'"
        } else {
            Add-Result "anthropic '$name'" $status $false $response.Content
        }
    }
} else {
    Write-Host "  (ningun modelo Anthropic registrado: es passthrough, no traduce desde OpenAI)" -ForegroundColor DarkGray
    Write-Host "  Para hablar Anthropic contra un modelo GPT, usa el puente del lab 12." -ForegroundColor DarkGray
}

# --------------------------------------------------------------------------------------------
Write-Step "4. Servidores MCP  (POST /default/toolservers/<nombre>/mcp)"

$toolservers = (Invoke-RestMethod -Uri "$workspace/toolservers?api-version=$apiVersion" -Headers $arm).value
foreach ($server in $toolservers) {
    $body = @{ jsonrpc = "2.0"; id = 1; method = "tools/list"; params = @{} } | ConvertTo-Json
    # El transporte MCP negocia SSE: sin este Accept el servidor responde 406.
    $response = Invoke-WebRequest -Uri "$gateway/default/toolservers/$($server.name)/mcp" -Method Post `
        -Headers @{ "api-key" = $key; "Accept" = "application/json, text/event-stream" } `
        -ContentType "application/json" -Body $body -SkipHttpErrorCheck -TimeoutSec 90
    $status = [int]$response.StatusCode
    if ($status -eq 200) {
        # La respuesta puede venir como SSE ("data: {...}") o como JSON plano.
        $text = $response.Content
        $json = if ($text -match '(?m)^data:\s*(\{.*\})') { $Matches[1] } else { $text }
        $tools = ($json | ConvertFrom-Json).result.tools
        # Un PUT fallido sobre un toolserver lo deja a medias: responde 200 pero federa 0
        # herramientas. Por eso la lista vacía cuenta como fallo, no como éxito.
        $count = @($tools).Count
        if ($count -gt 0) {
            Add-Result "mcp '$($server.name)' tools/list" $status $true "$count herramientas: $(($tools | ForEach-Object { $_.name }) -join ', ')"
        } else {
            Add-Result "mcp '$($server.name)' tools/list" $status $false "0 herramientas: borra y recrea el toolserver con ./aigw-cleanup.ps1 -Only toolservers"
        }
    } else {
        Add-Result "mcp '$($server.name)' tools/list" $status $false $response.Content
    }
}
if (-not $toolservers) { Write-Host "  (ningun servidor MCP registrado)" -ForegroundColor DarkGray }

# --------------------------------------------------------------------------------------------
Write-Step "5. Autenticacion"

# Sin clave el gateway tiene que rechazar: si esto devuelve 200, algo está mal configurado.
$body = @{ model = $chatModels[0]; messages = @(@{ role = "user"; content = "hola" }); max_tokens = 5 } | ConvertTo-Json -Depth 5
$response = Invoke-WebRequest -Uri "$gateway/default/models/openai/v1/chat/completions" -Method Post `
    -ContentType "application/json" -Body $body -SkipHttpErrorCheck -TimeoutSec 60
$status = [int]$response.StatusCode
Add-Result "peticion sin api-key" $status ($status -eq 401) $(if ($status -eq 401) { "rechazada, correcto" } else { "deberia devolver 401" })

# --------------------------------------------------------------------------------------------
Write-Step "Resumen"
$results | Format-Table -AutoSize
$failed = @($results | Where-Object { $_.OK -eq "NO" }).Count
if ($failed -eq 0) {
    Write-Host "Todo correcto: $($results.Count) pruebas superadas." -ForegroundColor Green
} else {
    Write-Host "$failed de $($results.Count) pruebas fallaron." -ForegroundColor Red
}
Write-Host "`nPara probar las politicas: ./aigw-policies-test.ps1 -GatewayName $GatewayName -GatewayResourceGroup $GatewayResourceGroup" -ForegroundColor Cyan
Write-Host "Para ver las metricas:     ./aigw-metrics.ps1" -ForegroundColor Cyan
