# Lab 12 · Claude Code sobre modelos OpenAI, sin LiteLLM

## Objetivo
Que **Claude Code** use los modelos **OpenAI** de Foundry (`gpt-4.1-mini`) **sin ninguna pieza
extra**: la traducción de protocolo Anthropic ↔ OpenAI la hace **la propia política de APIM**.

Es la tercera respuesta a la pregunta del [lab 08](08-cliente-claude-code.md), y la que elimina
el contenedor:

```
Lab 08   Claude Code ──► LiteLLM ──► APIM ──► Foundry (OpenAI)   traduce un proxy que operas tú
Lab 11   Claude Code ──────────────► APIM ──► Foundry (Claude)   mismo protocolo, requiere Marketplace
Lab 12   Claude Code ──────────────► APIM ──► Foundry (OpenAI)   traduce el gateway
                                      ▲
                              la traducción vive aquí
```

> **¿Y la *unified model API* de APIM?** No sirve para este caso. Es la traducción **contraria**:
> el cliente habla **OpenAI** y el backend es Anthropic
> ([doc oficial](https://learn.microsoft.com/azure/api-management/unified-model-api):
> *"Client applications use one familiar API format — the OpenAI Chat Completions API"*).
> Aquí el cliente habla Anthropic, así que la traducción se escribe en la política.

---

## Cuándo tiene sentido

| Situación | Ruta |
|-----------|------|
| El cliente ya tiene modelos OpenAI y **no quiere desplegar nada más** | **Este lab** |
| El cliente quiere modelos **Claude** de verdad | [Lab 11](11-claude-en-foundry.md) |
| Se necesita *streaming* token a token, o ~100 proveedores distintos | [Lab 08](08-cliente-claude-code.md) (LiteLLM) |

---

## Paso 1 · Desplegar el puente

Ya va incluido en la plantilla ([`infra/modules/anthropic-bridge.bicep`](../infra/modules/anthropic-bridge.bicep)),
así que se aplica con el despliegue normal:

```powershell
.\scripts\deploy.ps1
# o, si reutilizas un Foundry existente:
.\scripts\deploy-reuse.ps1 -FoundryResourceGroup rg-apim-workshop
```

Crea una API `anthropic-bridge` con **path `claude`** y tres operaciones:

| Operación | Qué hace |
|-----------|----------|
| `POST /v1/messages` | El puente en sí ([política](../infra/policies/anthropic-messages-policy.xml)) |
| `POST /v1/messages/count_tokens` | Estima tokens en el gateway (Azure OpenAI no tiene equivalente) |
| `GET /v1/models` | Anuncia los despliegues disponibles en formato Anthropic |

Reutiliza el **mismo `aoai-pool`, el mismo producto y la misma clave** que la API del lab 01, así
que hereda balanceo, circuit breaker, Managed Identity y métricas de tokens sin duplicar nada.

---

## Paso 2 · Apuntar Claude Code

```powershell
$env:ANTHROPIC_BASE_URL = "https://<tu-apim>.azure-api.net/claude"
$env:ANTHROPIC_API_KEY  = "<clave-de-suscripcion-APIM>"   # scripts\get-keys.ps1
$env:ANTHROPIC_MODEL = "chat"
$env:ANTHROPIC_SMALL_FAST_MODEL = "chat"
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "1047576"           # silencia el aviso de modelo desconocido
claude
```

Sin contenedor, sin `docker compose`, sin puerto 4000.

> ⚠️ **`ANTHROPIC_API_KEY`, no `ANTHROPIC_AUTH_TOKEN`.** La API acepta la clave en la cabecera
> `x-api-key`, que es la nativa de Anthropic. `ANTHROPIC_AUTH_TOKEN` envía
> `Authorization: Bearer …`, que APIM no reconoce como clave de suscripción → 401.

`ANTHROPIC_MODEL` admite **cualquier nombre de despliegue** de Foundry. Si mandas un `claude-*`
(lo que hace Claude Code por defecto) cae al despliegue por defecto, `{{anthropic-bridge-default-model}}`.

Comprobación rápida sin cliente:

```powershell
$key  = "<clave>"
$body = '{"model":"chat","max_tokens":64,"messages":[{"role":"user","content":"Di PONG"}]}'
curl -s -X POST "https://<tu-apim>.azure-api.net/claude/v1/messages" `
  -H "x-api-key: $key" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" `
  --data-raw $body
```

Devuelve un objeto Anthropic (`"type":"message"`, `content[].type=text`, `stop_reason`, `usage`).

---

## Paso 3 · Ver el gobierno aplicado

Es el mismo de siempre, y ese es justo el argumento comercial:

- El KQL del [lab 03](03-metricas-y-costes.md) muestra los tokens de Claude Code, porque la
  política emite `llm-emit-token-metric` en el namespace `ai-gateway`.
- Cada respuesta trae `x-tokens-consumed` y `x-tokens-remaining` del [lab 02](02-token-limit.md).
- Si añades `llm-content-safety` ([lab 06](06-content-safety.md)) también protege a Claude Code:
  el cuerpo ya es OpenAI cuando llegan las políticas LLM.

---

## Qué traduce exactamente la política

| Anthropic | OpenAI |
|-----------|--------|
| `system` (string **y** array de bloques) | mensaje `role:"system"` |
| `content` como string o array de bloques | `content` string o partes |
| `image` base64 | `image_url` con *data URL* |
| `tools[].input_schema` | `tools[].function.parameters` |
| `tool_choice: any` / `tool` | `required` / `{type:"function"…}` |
| bloque `tool_use` | `tool_calls` |
| bloque `tool_result` | mensaje `role:"tool"` |
| `stop_sequences` | `stop` |
| `stop_reason` ⇦ | `finish_reason` |
| `usage.input_tokens` ⇦ | `usage.prompt_tokens` |

Los errores también se devuelven en formato Anthropic (`{"type":"error","error":{…}}`), que es lo
que el cliente espera para reintentar bien.

---

## Limitaciones honestas

1. **El *streaming* es sintético.** APIM no puede transformar un flujo SSE *chunk* a *chunk* desde
   una política, así que el puente llama al backend **sin streaming** y genera al final la secuencia
   completa de eventos Anthropic (`message_start` → `content_block_*` → `message_delta` →
   `message_stop`). Claude Code funciona, pero **el texto aparece de golpe**, no token a token.
   Es la única diferencia funcional real frente a LiteLLM.
2. **`max_tokens` se acota a 16384.** Claude Code envía valores muy altos que Azure OpenAI
   rechazaría con un 400.
3. **`count_tokens` es una estimación**, no el tokenizador exacto de Anthropic.
4. **Un modelo OpenAI no es Claude.** Cambia el comportamiento del agente; si el cliente quiere
   Claude de verdad, el camino es el [lab 11](11-claude-en-foundry.md).

---

## Dimensionar el límite de tokens

El `llm-token-limit` del puente vale **200 000 TPM** por defecto, muy por encima de los 1 000-2 000
del resto del workshop, y es a propósito: el *system prompt* de Claude Code, con todas las
definiciones de sus herramientas, ronda **6-15k tokens en cada petición**. Con el límite de la demo,
el cliente recibe `429 · Token limit is exceeded` antes de poder hacer nada.

Se ajusta sin tocar la política:

```bicep
module anthropicBridge 'modules/anthropic-bridge.bicep' = {
  params: { tokensPerMinute: 200000 }   // -> valor con nombre anthropic-bridge-tpm
}
```

> **Moraleja para el cliente:** un cliente agéntico consume uno o dos órdenes de magnitud más que
> un chat. Conviene medirlo con el [lab 03](03-metricas-y-costes.md) **antes** de fijar cuotas.

### El otro techo: la cuota del despliegue en Foundry

Subir el límite de APIM no basta. El `429` puede venir **de Foundry**, no del gateway, y se
distingue por el mensaje:

```
API Error: Request rejected (429) · Your requests to gpt-4.1-mini for chat
in swedencentral have exceeded rate limit.
```

Un cliente agéntico manda su system prompt entero en **cada** petición: entre 6 000 y 15 000 tokens
antes de que el usuario escriba nada. Con `sku.capacity = 20` (**20 000 TPM**) una sola petición de
Claude Code agota el despliegue. Por eso `chatCapacity` vale **150** en
[`infra/modules/foundry.bicep`](../infra/modules/foundry.bicep). Si desplegaste el workshop antes de
ese cambio, amplía los dos despliegues a mano:

```powershell
az cognitiveservices account deployment create -g rg-apim-workshop -n <cuenta> `
  --deployment-name chat --model-name gpt-4.1-mini --model-version 2025-04-14 `
  --model-format OpenAI --sku-name GlobalStandard --sku-capacity 150
```

Con 150 (150 000 TPM) en los dos backends, Claude Code completa tareas con herramientas sin
tropezar. Es un buen momento para enseñar el [balanceo del lab 04](04-balanceo-y-failover.md):
el `aoai-pool` reparte entre los dos despliegues y duplica el techo efectivo.

---

## ⚠️ Gotcha de APIM: valores con nombre dentro de CDATA

APIM **no sustituye `{{valor-con-nombre}}` dentro de un bloque `<![CDATA[ … ]]>`**. No da error de
despliegue: en tiempo de ejecución devuelve el literal `{{nombre}}`. Funciona en atributos
(`value="@{…}"`) pero no en CDATA.

```xml
<!-- ❌ dentro de CDATA: devuelve el literal -->
<return-response><set-body><![CDATA[@{ return "{{anthropic-bridge-models}}"; }]]></set-body></return-response>

<!-- ✅ se lee fuera y se consume por variable -->
<set-variable name="modelList" value="{{anthropic-bridge-models}}" />
<return-response><set-body><![CDATA[@{
    var list = (string)context.Variables["modelList"];
}]]></set-body></return-response>
```

Es el patrón que usa [`anthropic-models-policy.xml`](../infra/policies/anthropic-models-policy.xml).

---

## Siguiente
⬅️ Vuelve al [README](../README.md) · compara con el [Lab 08](08-cliente-claude-code.md) y el [Lab 11](11-claude-en-foundry.md)
