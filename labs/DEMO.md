# 🎬 Guión de demo (runbook del presentador)

Secuencia lista para presentar sobre el gateway **ya desplegado y verificado**:
`https://apim-aigw-dev-01.azure-api.net` (APIM StandardV2 reutilizado).

Cada acto: **qué mostrar → comando copy-paste → qué decir**. Duración total ~25-35 min
(sin los opcionales). Los labs detallados están en esta misma carpeta si quieres profundizar.

---

## 0 · Antes de empezar (1 min, fuera de cámara)

```powershell
cd apim-foundry-ai-gateway-workshop
./scripts/get-keys.ps1 -ApimName apim-aigw-dev-01 -ResourceGroup rg-aigateway-dev-01
# copia los valores que imprime:
$env:APIM_GATEWAY_URL="https://apim-aigw-dev-01.azure-api.net"
$env:APIM_SUBSCRIPTION_KEY="<clave-que-te-dio-el-script>"
```

**Frase de apertura:** *"Todo lo que veréis pasa por un único punto gobernado —APIM como AI
Gateway— delante de Azure AI Foundry. El desarrollador usa su herramienta favorita; la empresa
mantiene control de coste, seguridad e identidad."*

---

## Acto 1 · Primera llamada gobernada + keyless (3 min)
**Mostrar:** una llamada normal tipo OpenAI que en realidad atraviesa APIM.

```powershell
curl -s -X POST "$env:APIM_GATEWAY_URL/openai/deployments/chat/chat/completions?api-version=2024-10-21" `
  -H "api-key: $env:APIM_SUBSCRIPTION_KEY" -H "Content-Type: application/json" `
  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Explica un AI Gateway en una frase\"}]}'
```

**Decir:** *"El cliente solo tiene la clave de APIM. **Nunca** ve las claves de Foundry: APIM se
autentica con Managed Identity (keyless). Cambiar de modelo o rotar credenciales no toca al
cliente."* → referencia lab 07.

---

## Acto 2 · Límite de tokens (rate limiting) (3 min)
**Mostrar:** la cabecera de presupuesto y un 429 al pasarse.

```powershell
# Fíjate en la cabecera x-tokens-remaining
(Invoke-WebRequest -Uri "$env:APIM_GATEWAY_URL/openai/deployments/chat/chat/completions?api-version=2024-10-21" `
  -Method Post -Headers @{ "api-key"=$env:APIM_SUBSCRIPTION_KEY; "Content-Type"="application/json" } `
  -Body '{"messages":[{"role":"user","content":"hola"}],"max_tokens":10}' -UseBasicParsing).Headers["x-tokens-remaining"]

# Fuerza el límite (bucle): verás pasar de 200 a 429
1..25 | ForEach-Object {
  $c = try { (Invoke-WebRequest -Uri "$env:APIM_GATEWAY_URL/openai/deployments/chat/chat/completions?api-version=2024-10-21" `
    -Method Post -Headers @{ "api-key"=$env:APIM_SUBSCRIPTION_KEY; "Content-Type"="application/json" } `
    -Body '{"messages":[{"role":"user","content":"escribe un poema largo"}],"max_tokens":400}' -UseBasicParsing).StatusCode }
       catch { $_.Exception.Response.StatusCode.value__ }
  Write-Host -NoNewline "$c "
}
```

**Decir:** *"Cuota por clave = por equipo o por app. Protege coste y capacidad. En producción se
combina con quotas por día/mes."* → lab 02.

---

## Acto 3 · Métricas de tokens y coste (4 min)
**Mostrar:** Portal → Application Insights **`appi-aigw-dev-01`** → Logs → pega el KQL:

```kusto
customMetrics
| where name in ("TotalTokens","PromptTokens","CompletionTokens")
| extend sub = tostring(customDimensions["Subscription ID"]),
         deploy = tostring(customDimensions["Deployment"])
| summarize tokens = sum(valueSum) by name, deploy, bin(timestamp, 5m)
| order by timestamp desc
```

**Decir:** *"Cada llamada emite tokens de prompt y completion con dimensiones (suscripción, API,
despliegue). Multiplicando por el precio del modelo tienes **FinOps por equipo**. Aquí se
construye el Workbook de coste."* → lab 03.

> Si las métricas tardan, ten una captura de respaldo: pueden tardar 2-5 min en ingestar.

---

## Acto 4 · Balanceo de carga y failover (3 min)
**Mostrar:** que hay 2 backends de Foundry tras un pool con circuit breaker.

```powershell
az apim api show -g rg-aigateway-dev-01 --service-name apim-aigw-dev-01 --api-id ai-gateway --query "name" -o tsv
# En el Portal: APIs -> Backends -> aoai-pool (2 miembros) y aoai-0/aoai-1 (circuit breaker)
```

**Decir:** *"Reparto entre despliegues; si uno devuelve 429/5xx, el circuit breaker lo saca 30 s
y el tráfico sigue por el otro. Base para multi-región y alta disponibilidad."* → lab 04.

---

## Acto 5 · Claude Code ("cloud code") usando Foundry (5 min) — el momento estrella
**Mostrar:** Claude Code, la herramienta del cliente, respondiendo con modelos de Foundry, y el
tráfico contabilizado en APIM.

```powershell
cd clients/litellm
Copy-Item .env.example .env    # edita APIM_GATEWAY_URL, APIM_SUBSCRIPTION_KEY, LITELLM_MASTER_KEY
docker compose up -d           # puente Anthropic->OpenAI en localhost:4000

$env:ANTHROPIC_BASE_URL="http://localhost:4000"
$env:ANTHROPIC_AUTH_TOKEN="sk-workshop-1234"   # = LITELLM_MASTER_KEY
claude    # usa Claude Code normal; por detrás va a Foundry vía APIM
```

**Decir:** *"El dev sigue usando Claude Code igual. Pero cada token pasa por APIM: mismos
límites, mismas métricas, misma seguridad que cualquier otra app. Reutilizamos **vuestros**
modelos de Foundry, con vuestro coste y vuestra región."* → lab 08.

> Repite el KQL del Acto 3: verás el tráfico de Claude Code contabilizado.

---

## Acto 6 · GitHub Copilot CLI + gh (2 min) — la alternativa nativa
```powershell
gh extension install github/gh-copilot
gh copilot suggest "comprimir una carpeta en tar.gz"
```

**Decir:** *"Si el cliente vive en GitHub, Copilot es llave en mano (modelos gestionados por
GitHub, cero infra). APIM+Foundry es para **sus propios modelos**, control de datos y coste por
equipo. Son complementarias."* → lab 09.

---

## Opcionales (si hay tiempo / interés)

### Caché semántica (5 min setup) → lab 05
Despliega Azure Managed Redis, conéctalo como caché externa, añade el snippet
`infra/policies/snippets/05-semantic-cache.xml`. Demo: dos prompts parecidos; el segundo sale de
caché (latencia ↓, tokens ≈ 0).

### Content safety / jailbreak (5 min setup) → lab 06
Crea Azure AI Content Safety, añade `snippets/06-content-safety.xml`. Demo: un intento de
jailbreak recibe **403** en el gateway, sin llegar al modelo.

### Gobierno de MCP (hablado) → lab 10
Exponer una API como servidor MCP y aplicarle rate limiting. Encaja con Claude Code y Copilot.

---

## Cierre (1 min)
*"Una sola puerta: cualquier herramienta de dev, cualquier modelo de Foundry, con límites,
coste, seguridad e identidad centralizados. Y todo es Infra as Code en el repo, reutilizable
sobre vuestro APIM existente."*

**Recordatorio post-demo:** el APIM Developer redundante se borra con
`./scripts/cleanup.ps1 -Mode RedundantApim` (los Foundry se conservan: son los backends).
