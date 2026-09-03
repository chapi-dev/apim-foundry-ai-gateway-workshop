# 🎬 Guión de demo (runbook del presentador)

> ¿Prefieres no tocar la consola? Hay una versión equivalente **sólo con el portal**:
> [DEMO-portal.md](DEMO-portal.md).

Secuencia lista para presentar sobre el gateway **ya desplegado y verificado**:
`https://apim-aigw-dev-01.azure-api.net` (APIM StandardV2 reutilizado).

Cada acto: **qué mostrar → comando copy-paste → qué decir**. Duración total ~25-35 min
(sin los opcionales). Los labs detallados están en esta misma carpeta si quieres profundizar.

---

## 0 · Antes de empezar (1 min, fuera de cámara)

> **Abre PowerShell 7** (`pwsh`), no *Windows PowerShell* 5.1: allí `curl` es un alias de
> `Invoke-WebRequest` y los comandos fallan con *"Cannot bind parameter 'Headers'"*.

```powershell
cd apim-foundry-ai-gateway-workshop
./scripts/get-keys.ps1 -ApimName apim-aigw-dev-01 -ResourceGroup rg-aigateway-dev-01
# copia los valores que imprime:
$env:APIM_GATEWAY_URL="https://apim-aigw-dev-01.azure-api.net"
$env:APIM_SUBSCRIPTION_KEY="<clave-que-te-dio-el-script>"
```

**Ojo:** las variables viven solo en esa ventana. Si abres otra consola (p. ej. para Claude
Code en el Acto 5), hay que repetir este paso allí.

**Frase de apertura:** *"Todo lo que veréis pasa por un único punto gobernado —APIM como AI
Gateway— delante de Azure AI Foundry. El desarrollador usa su herramienta favorita; la empresa
mantiene control de coste, seguridad e identidad."*

---

## Acto 1 · Primera llamada gobernada + keyless (3 min)
**Mostrar:** una llamada normal tipo OpenAI que en realidad atraviesa APIM.

```powershell
$uri  = "$env:APIM_GATEWAY_URL/openai/deployments/chat/chat/completions?api-version=2024-10-21"
$hdr  = @{ "api-key" = $env:APIM_SUBSCRIPTION_KEY }
$body = '{"messages":[{"role":"user","content":"Explica un AI Gateway en una frase"}]}'

$r = Invoke-RestMethod -Uri $uri -Method Post -Headers $hdr -ContentType "application/json" -Body $body
$r.choices[0].message.content
```

**Decir:** *"El cliente solo tiene la clave de APIM. **Nunca** ve las claves de Foundry: APIM se
autentica con Managed Identity (keyless). Cambiar de modelo o rotar credenciales no toca al
cliente."* → referencia lab 07.

---

## Acto 2 · Límite de tokens (rate limiting) (3 min)
**Mostrar:** el presupuesto bajando petición a petición, y un 429 al pasarse.

```powershell
# El presupuesto se consume: fíjate en "restantes"
$body = '{"messages":[{"role":"user","content":"Escribe un poema largo"}],"max_tokens":500}'
1..6 | ForEach-Object {
  $r = Invoke-WebRequest -Uri $uri -Method Post -Headers $hdr -ContentType "application/json" -Body $body -UseBasicParsing
  "consumidos={0}  restantes={1}" -f ($r.Headers["x-tokens-consumed"] -join ''), ($r.Headers["x-tokens-remaining"] -join '')
}
```

> ⚠️ **Prepara el 429 antes de la demo.** Con el techo de 2000 TPM no salta: cada respuesta tarda
> ~6 s en generar ~400 tokens y la ventana de un minuto se renueva antes de acumular el límite.
> Baja `tokens-per-minute` a **200** en el editor del portal (APIs → `ai-gateway` → Design →
> *All operations* → `</>`) y el bucle da `200 429 200 429 429…` a la segunda petición.
> **Devuélvelo a 2000 al terminar.**

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
tráfico contabilizado en APIM. **Sin instalar nada**: la traducción Anthropic → OpenAI la hace
la propia política de APIM.

```powershell
$env:ANTHROPIC_BASE_URL="$env:APIM_GATEWAY_URL/claude"
$env:ANTHROPIC_API_KEY=$env:APIM_SUBSCRIPTION_KEY      # va en x-api-key, la cabecera de Anthropic
$env:ANTHROPIC_MODEL="chat"
$env:ANTHROPIC_SMALL_FAST_MODEL="chat"
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS="1047576"          # silencia el aviso de modelo desconocido
claude    # usa Claude Code normal; por detrás va a Foundry vía APIM
```

**Decir:** *"El dev sigue usando Claude Code igual. Pero cada token pasa por APIM: mismos
límites, mismas métricas, misma seguridad que cualquier otra app. Reutilizamos **vuestros**
modelos de Foundry, con vuestro coste y vuestra región — y sin desplegar ninguna pieza extra,
porque el gateway traduce el protocolo."* → lab 12.

> Repite el KQL del Acto 3: verás el tráfico de Claude Code contabilizado.
> ⚠️ El texto aparece **de golpe**, no token a token: el *streaming* que devuelve el puente es
> sintético (APIM no transforma SSE *chunk* a *chunk*). Anticípalo antes de que lo pregunten.

**Variante con LiteLLM** (enséñala si el cliente necesita *streaming* real o muchos proveedores):

```powershell
cd clients/litellm
Copy-Item .env.example .env    # edita APIM_GATEWAY_URL, APIM_SUBSCRIPTION_KEY, LITELLM_MASTER_KEY
docker compose up -d           # puente Anthropic->OpenAI en localhost:4000
$env:ANTHROPIC_BASE_URL="http://localhost:4000"
$env:ANTHROPIC_AUTH_TOKEN="sk-workshop-1234"   # = LITELLM_MASTER_KEY
claude
```
→ lab 08. **Decir:** *"Mismo resultado, pero aquí hay un contenedor que alguien tiene que operar."*

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
