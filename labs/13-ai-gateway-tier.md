# Lab 13 · El SKU *AI Gateway* (preview) — la vía "moderna"

## Objetivo
Montar el mismo gobierno de los labs 01–07 y 10 sobre el **tier AI Gateway (preview)** de APIM:
un SKU nuevo, específico para tráfico de IA, donde **no se escriben políticas XML** — los modelos,
las herramientas MCP y las políticas se declaran como **objetos de configuración**.

> **Preview.** Sin SLA, precio no anunciado y solo en **East US 2** y **Sweden Central**.
> Es un **capítulo alternativo** del workshop, no un sustituto de los labs clásicos.
> Para producción hoy, el camino soportado sigue siendo el SKU clásico (v2).

---

## En qué se diferencia del APIM clásico

| | APIM clásico (v2) | AI Gateway tier (preview) |
|---|---|---|
| Unidad de configuración | API + operaciones + **política XML** | **Modelos**, **MCP servers**, **políticas** declarativas |
| Autoría de políticas | XML con expresiones C# | Formulario/JSON, **sin XML ni expresiones** |
| Credencial de cliente | `subscription-key` de un *producto* | **runtime access key** en cabecera `api-key` |
| Ruta | la que definas (`/aoai`, `/claude`, …) | fija: `/default/models/...`, `/default/toolservers/...` |
| Backend Foundry | `backend` + `authentication-managed-identity` | **Import from Foundry** con Managed Identity |

La consecuencia importante: **lo que no exista como política declarativa, no se puede
implementar**. No hay una vía de escape a XML.

---

## Qué se porta y qué no

| Lab | Capacidad | ¿Portable? | Nota |
|-----|-----------|-----------|------|
| [01](01-desplegar-y-primera-llamada.md) | Primera llamada gobernada | ✅ | `Add models` + runtime access key |
| [02](02-token-limit.md) | Límite de tokens | ✅ | Política *Token rate limit*: por minuto, **hora o día** |
| [03](03-metricas-y-costes.md) | Métricas y coste | ⚠️ | Solo métrica OTel `gen_ai_client_token_usage`; **sin dimensiones propias** |
| [04](04-balanceo-y-failover.md) | Balanceo / failover | ❌ | La API exige que `deployment.modelName` sea **único por workspace**: dos Foundry con un despliegue `chat` no pueden convivir |
| [05](05-semantic-cache.md) | Caché semántica | ❌ | No existe como política en preview |
| [06](06-content-safety.md) | Content safety / jailbreak | ✅ | Política *Content safety*, con Prompt Shields y blocklists |
| [07](07-managed-identity.md) | Managed Identity (keyless) | ✅ | Es el modo **recomendado** del asistente de importación |
| [10](10-mcp.md) | Gobierno de MCP | ✅➕ | Además: OpenAPI→tools y **+1000 conectores** integrados |
| [11](11-claude-en-foundry.md) | Claude nativo | ✅ | *Anthropic Messages passthrough* |
| [12](12-claude-code-sin-litellm.md) | Claude Code → GPT sin LiteLLM | ❌ | Necesita traducción en política XML → ver [abajo](#y-el-lab-12) |

Los dos huecos reales frente al SKU clásico son **caché semántica** y **balanceo entre
despliegues**. Conviene decirlo tal cual al cliente.

---

## Paso 0 · Registrar el feature flag

El tier no aparece — ni por portal ni por API — hasta registrarlo en la suscripción:

```powershell
az feature register --namespace Microsoft.ApiManagement --name AIGatewayPreview
az provider register --namespace Microsoft.ApiManagement
```

La propagación a ARM no es inmediata; hasta que termina, la API de gestión
`2026-05-01-preview` responde *"No registered resource provider found…"*.

```powershell
az feature show --namespace Microsoft.ApiManagement --name AIGatewayPreview --query properties.state -o tsv
```

## Paso 1 · Dar acceso keyless a Foundry

El asistente de importación asigna el rol por ti **si tienes permiso**. Para hacerlo explícito
(y que la demo no dependa de ello):

```powershell
$principal = az apim show -g <rg-gateway> -n <gateway> --query identity.principalId -o tsv
foreach ($acct in @('aigwqyxvxaoai1','aigwqyxvxaoai2')) {
  az role assignment create --assignee-object-id $principal --assignee-principal-type ServicePrincipal `
    --role '53ca6127-db72-4b80-b1b0-d745d6d5456d' `   # Foundry User
    --scope "/subscriptions/<sub>/resourceGroups/rg-apim-workshop/providers/Microsoft.CognitiveServices/accounts/$acct"
}
```

## Paso 2 · Importar los modelos

**Models → Add models → Import from Foundry**: elige suscripción y recurso, y el asistente
**descubre los despliegues** solo. En *Provider details* escoge **Managed identity**.

También se puede hacer por ARM (ver el bloque de abajo), pero hay un detalle que cuesta un rato
descubrir porque el síntoma engaña:

> ⚠️ **El `model` del cuerpo tiene que ser el nombre del *despliegue*, no el del modelo.**
> El gateway enruta por **coincidencia exacta** de `deployment.modelName`, y cuando no encuentra
> nada responde **`404` sin cuerpo** — el mismo error que si la ruta no existiera. Con un
> despliegue llamado `chat` que sirve `gpt-4.1-mini`:
>
> ```
> {"model":"gpt-4.1-mini"}  -> 404      el nombre del modelo NO vale
> {"model":"chat"}          -> 200      el nombre del despliegue SI
> ```
>
> El nombre que le pongas al recurso en el gateway (`.../models/<este>`) es solo una etiqueta:
> no interviene en el enrutado.

> **`foundry.endpoint` es obligatorio de facto** y tiene que ser el de *AI Foundry API*
> (`https://<cuenta>.services.ai.azure.com/`), que sale en
> `az cognitiveservices account show --query properties.endpoints`. Si lo omites, el modelo
> falla al crearse con `Parent provider '<p>' has no projected backend; cannot project model`.

> La unicidad se comprueba sobre **`deployment.modelName`**, no sobre el nombre que le pongas al
> modelo:
>
> ```
> ValidationError: A model with deployment.modelName 'chat' already exists in this workspace.
>                  Model names must be unique within a workspace.
> ```
>
> Como los dos Foundry del workshop tienen un despliegue llamado `chat`, **no puedes registrar
> los dos**. Se sortea renombrando: crea en el segundo un despliegue `chat-eu` y regístralo
> aparte. Pero eso te deja **dos modelos con nombres distintos**, no uno balanceado entre dos
> backends — por eso el [lab 04](04-balanceo-y-failover.md) sigue sin ser reproducible.

<details>
<summary>Modelo de objetos ARM (por si quieres inspeccionarlo)</summary>

Los assets **no cuelgan del servicio** sino de un workspace fijo llamado `default`, y los tipos
clásicos (`apis`, `backends`, `products`, `namedValues`, `subscriptions`, `policies`) devuelven
`400 Method not allowed in AIGateway pricing tier`:

```
.../service/<gw>/workspaces/default/modelProviders           # kind: Foundry | Custom
.../service/<gw>/workspaces/default/modelProviders/<p>/models
.../service/<gw>/workspaces/default/models                   # solo lectura, agregado
.../service/<gw>/workspaces/default/toolservers
.../service/<gw>/apikeys                                     # ojo: a nivel de servicio
```

Un proveedor Foundry se describe así (`api-version=2025-09-01-preview`; las versiones
posteriores que cita la doc, incluida `2026-05-01-preview`, todavía no responden):

```json
{ "properties": { "kind": "Foundry", "displayName": "Foundry Sweden 1",
  "foundry": { "endpoint": "https://<cuenta>.services.ai.azure.com/",
    "resourceIds": [ "/subscriptions/.../accounts/<cuenta>" ],
    "authentication": { "kind": "ManagedIdentity" } } } }
```

Y un modelo, donde `supportedEndpoints` son **rutas relativas** y `modelName` es el nombre del
**despliegue** en Foundry (el valor que los clientes mandan en `model`):

```json
{ "properties": { "supportedEndpoints": [ "/chat/completions" ],
  "deployment": { "modelName": "chat", "resourceId": "/subscriptions/.../accounts/<cuenta>" } } }
```

Un servidor MCP usa `type` (no `kind`), con valores `Mcp`, `OpenApi` o `Connector`, y cada
endpoint indica su origen en `mcp.url` (inline) o `backendId` (referencia):

```json
{ "properties": { "displayName": "Microsoft Learn", "type": "Mcp",
  "endpoints": [ { "name": "learn", "kind": "Mcp",
    "mcp": { "url": "https://learn.microsoft.com/api/mcp" },
    "authentication": { "kind": "None" } } ] } }
```

Un proveedor `Custom` (para Anthropic, Bedrock, Vertex o cualquier endpoint propio) lleva la
credencial anidada dos niveles — `apiKey` es un objeto, no una cadena:

```json
{ "properties": { "kind": "Custom", "displayName": "Mi proveedor",
  "custom": { "endpoint": "https://...",
    "authentication": { "kind": "ApiKey",
      "apiKey": { "headerName": "x-api-key", "value": "<secreto>" } } } } }
```

Ojo: los Foundry del workshop se despliegan con `disableLocalAuth: true` (keyless, que es el
objetivo del [lab 07](07-managed-identity.md)), así que **no hay clave que pegar** en un
proveedor `Custom` que apunte a ellos: para Foundry hay que usar `kind: Foundry` con Managed
Identity.

</details>

## Paso 3 · Crear la runtime access key

**Keys → crear**. Sustituye a la clave de suscripción del producto. En preview la clave es
**de ámbito gateway**: da acceso a *todos* los assets publicados, no se puede acotar por modelo.

Un gateway recién creado ya trae una (`master`, *Built-in all-access subscription*). Para leerla
sin pasar por el portal:

```powershell
$svc = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<gw>"
az rest --method post --url "https://management.azure.com$svc/apikeys/master/listSecrets?api-version=2025-09-01-preview" --query primaryKey -o tsv
```

## Paso 4 · Políticas

**Policies →** cuatro tipos, aplicables al gateway entero o a un asset concreto:

| Política | Efecto | Equivalente clásico |
|----------|--------|---------------------|
| **Token rate limit** | `429` al superar tokens por minuto/hora/día | `llm-token-limit` |
| **Request rate limit** | `429` por número de peticiones | `rate-limit-by-key` |
| **Content safety** | `400` con Prompt Shields y blocklists | `llm-content-safety` |
| **IP filter** | `403` fuera de la lista permitida | `ip-filter` |

El contador de *Token rate limit* se reparte por **identidad del llamante** o por **IP**.

> Las políticas **solo se configuran por portal** en preview. La doc dice que en el control plane
> cada política es un objeto JSON, pero en `2025-09-01-preview` no hay recurso ARM que las
> exponga: `policies` devuelve `400 Method not allowed in AIGateway pricing tier` y el resto de
> nombres, `404`. Modelos y MCP sí son automatizables; las políticas, todavía no.

> ⚠️ Las cabeceras de cuota **cambian de nombre** respecto al SKU clásico:
> aquí son `remaining-tokens` / `consumed-tokens` (en el clásico, `x-tokens-remaining` /
> `x-tokens-consumed`). Cualquier cliente que las lea hay que tocarlo.

## Paso 5 · Probar

```powershell
$g   = "https://<gateway>.azure-api.net"
$key = "<runtime-access-key>"

# OJO: "model" es el nombre del DESPLIEGUE en Foundry, no el del modelo
$body = @{ model = "chat"; messages = @(@{ role = "user"; content = "Hola" }) } | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "$g/default/models/openai/v1/chat/completions" -Method POST `
  -Headers @{ "api-key" = $key } -ContentType "application/json" -Body $body
```

Para embeddings, misma clave y misma raíz, cambiando la última parte de la ruta:

```powershell
$body = @{ model = "embeddings"; input = "hola mundo" } | ConvertTo-Json
Invoke-RestMethod -Uri "$g/default/models/openai/v1/embeddings" -Method POST `
  -Headers @{ "api-key" = $key } -ContentType "application/json" -Body $body
```

Fíjate en la ruta: el prefijo **`/default/models`** es fijo, y `openai/v1` es el *formato* de la
API, no el proveedor — Foundry, Azure OpenAI, Bedrock, Vertex y OpenAI comparten ese camino y se
distinguen por el campo `model`.

## Paso 6 · MCP

**MCP servers → Add MCP server**. Un mismo servidor federa tres tipos de backend —
**MCP remoto** (por URL), **spec OpenAPI** (convierte operaciones en tools) y **conectores
integrados** (+1000 SaaS, sin servidor que hospedar). Cada backend prefija sus tools con su
nombre, así que dos `create_issue` de orígenes distintos no chocan.

```
https://<gateway>.azure-api.net/default/toolservers/<server>/mcp
```

Con la misma `api-key`. Es el punto donde este SKU **supera** claramente al clásico.

Para comprobar que federa bien, pídele la lista de tools por JSON-RPC:

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
Invoke-RestMethod -Uri "$g/default/toolservers/learn/mcp" -Method POST `
  -Headers @{ "api-key" = $key; "Accept" = "application/json, text/event-stream" } `
  -ContentType "application/json" -Body $body
```

Apuntando el servidor al MCP público de Microsoft Learn (`https://learn.microsoft.com/api/mcp`),
la respuesta trae sus tres herramientas —`microsoft_docs_search`, `microsoft_code_sample_search`
y `microsoft_docs_fetch`— servidas ya por tu gateway y con tu clave, no con la del origen.

## Paso 7 · Observabilidad

El gateway emite la métrica OpenTelemetry **`gen_ai_client_token_usage`** hacia Application
Insights u otro destino OTLP.

> ⚠️ Se consulta con **PromQL**, no con KQL. Las consultas del [lab 03](03-metricas-y-costes.md)
> no valen aquí. El tráfico de tools MCP sí se ve en el portal vía App Insights, pero todavía
> **no** se exporta por OTLP.

---

## ¿Y el lab 12?

El [puente Anthropic→OpenAI](12-claude-code-sin-litellm.md) son ~27 KB de política XML. Aquí no
hay XML, y el proveedor Anthropic del tier es **passthrough**: reenvía el formato Messages tal
cual a `api.anthropic.com` inyectando la `x-api-key` del backend. **No traduce a OpenAI.**

Quedan dos salidas honestas:

1. **Dejar el puente en el APIM clásico** y presentarlos como dos gateways con propósitos
   distintos. Es lo más limpio.
2. **Encadenar**: en el tier nuevo, `Add models → Add a custom model` con endpoint
   `https://apim-aigw-dev-01.azure-api.net/claude`, cabecera de autenticación `x-api-key` y el
   *endpoint* **Anthropic messages**. Claude Code habla con el gateway moderno (que aplica
   límites y content safety) y el clásico hace la traducción.

```
Claude Code ─► AI Gateway (governance) ─► APIM clásico (traduce) ─► Foundry (GPT)
```

La opción 2 demuestra bien el gobierno, pero son **dos saltos** y dos facturas: úsala como
demo, no como arquitectura recomendada.

---

## Siguiente
➡️ Vuelve al [menú del README](../README.md) o al guión de demo [`DEMO-portal.md`](DEMO-portal.md).
