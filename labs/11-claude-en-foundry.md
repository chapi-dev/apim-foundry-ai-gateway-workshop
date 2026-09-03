# Lab 11 · Claude directamente en Foundry (sin LiteLLM)

En el [lab 08](08-cliente-claude-code.md) usamos **LiteLLM** como puente porque Claude Code habla
protocolo **Anthropic** y nuestros backends son modelos **OpenAI** (`gpt-4.1-mini`). Este lab
muestra la alternativa de producción: **desplegar un modelo Claude nativo en Foundry** y que
Claude Code (o cualquier cliente Anthropic) hable **directamente** con él a través de APIM,
**sin ninguna pieza de traducción**.

```
Claude Code  ──►  APIM (path /anthropic)  ──►  Azure AI Foundry (modelo Claude nativo)
   (Anthropic Messages API, mismo protocolo de extremo a extremo)
```

---

## Requisito previo: acceso a Azure Marketplace

Los modelos Claude en Foundry los ofrece **Anthropic a través de Azure Marketplace** (no son
first-party como los de OpenAI). El despliegue requiere:

- Una suscripción **de pago con método de pago activo** y **compras de Marketplace habilitadas**.
- Permisos para suscribir ofertas de Marketplace + rol **Contributor/Owner** en el grupo de recursos.

Habilitación de compras de Marketplace: Cost Management + Billing → cuenta de facturación →
Policies → **Azure Marketplace purchases = Allowed** (lo configura el owner del billing account).
Consulta también las [regiones soportadas por Anthropic](https://aka.ms/supported_anthropic_regions).

Listar los modelos Claude disponibles en tu cuenta/región:

```powershell
az cognitiveservices account list-models -n <cuenta> -g <rg> `
  --query "[?format=='Anthropic'].{name:name,version:version}" -o table
```

(En Sweden Central hay Haiku, Sonnet y Opus; **Haiku** es el más económico.)

---

## Paso 1 · Desplegar un modelo Claude (el más barato: Haiku)

El CLI `az cognitiveservices account deployment create` **no** admite el campo obligatorio
`modelProviderData`, así que se despliega por **REST/ARM** con `api-version=2025-10-01-preview`:

```powershell
$sub = "<subscriptionId>"; $rg = "rg-apim-workshop"; $acct = "aigwqyxvxaoai1"
$body = @{
  sku = @{ name = "GlobalStandard"; capacity = 1 }
  properties = @{
    model = @{ format = "Anthropic"; name = "claude-haiku-4-5"; version = "20251001" }
    # Metadatos obligatorios de Anthropic (rellena con los datos de tu organización):
    modelProviderData = @{ industry = "Technology"; organizationName = "<TuOrg>"; countryCode = "ES" }
  }
} | ConvertTo-Json -Depth 10
$tmp = Join-Path $env:TEMP "claude-deploy.json"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))

az rest --method put `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acct/deployments/claude-haiku?api-version=2025-10-01-preview" `
  --body "@$tmp"
Remove-Item $tmp
```

> El nombre del deployment (`claude-haiku`) es lo que usarás como `model` en las peticiones.
> Con Marketplace habilitado tarda ~1-2 min y queda en estado `Succeeded`.

---

## Paso 2 · Endpoint nativo de Claude en Foundry

Una vez desplegado, Foundry expone la **Anthropic Messages API** directamente:

- **Base URL:** `https://<cuenta>.services.ai.azure.com/anthropic`
- **Endpoint:** `https://<cuenta>.services.ai.azure.com/anthropic/v1/messages`
- **Auth:** Microsoft Entra ID (keyless, scope `https://ai.azure.com/.default`) o clave de la cuenta.

Prueba directa (clave de la cuenta):

```powershell
$key = az cognitiveservices account keys list -n aigwqyxvxaoai1 -g rg-apim-workshop --query key1 -o tsv
$body = '{"model":"claude-haiku","max_tokens":100,"messages":[{"role":"user","content":"Hola en una frase"}]}'
curl -s -X POST "https://aigwqyxvxaoai1.services.ai.azure.com/anthropic/v1/messages" `
  -H "x-api-key: $key" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" `
  --data-raw $body
```

---

## Paso 3 · Gobernarlo con APIM (recomendado)

Para no exponer Foundry directamente y mantener límites/métricas/identidad, se pone **APIM
delante** con una API nueva de path `anthropic` que reenvía a `…/anthropic`:

- **Backend:** `https://<cuenta>.services.ai.azure.com/anthropic`.
- **Keyless:** `authentication-managed-identity` con **`resource="https://ai.azure.com"`**
  (⚠️ scope distinto al de OpenAI, que es `https://cognitiveservices.azure.com`).
- Se pueden reutilizar las mismas políticas de `llm-token-limit` y `llm-emit-token-metric`
  (soportan el formato Anthropic), así que **el control de coste y cuota es idéntico** al del
  gateway OpenAI.

Esbozo de política (inbound):

```xml
<inbound>
  <base />
  <authentication-managed-identity resource="https://ai.azure.com"
      output-token-variable-name="managed-id-access-token" ignore-error="false" />
  <set-header name="Authorization" exists-action="override">
    <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
  </set-header>
  <llm-token-limit tokens-per-minute="1000" counter-key="@(context.Subscription.Id)"
      estimate-prompt-tokens="false" tokens-consumed-header-name="x-tokens-consumed"
      remaining-tokens-header-name="x-tokens-remaining" />
  <llm-emit-token-metric namespace="anthropic">
    <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
  </llm-emit-token-metric>
  <set-backend-service backend-id="claude-foundry" />
</inbound>
```

---

## Paso 4 · Apuntar Claude Code directamente (sin LiteLLM)

Como el protocolo es Anthropic de extremo a extremo, Claude Code va directo a APIM:

```powershell
$env:ANTHROPIC_BASE_URL="https://apim-aigw-dev-01.azure-api.net/anthropic"
$env:ANTHROPIC_API_KEY="<clave-de-suscripcion-APIM>"   # NO una clave de Anthropic
claude
```

> Configura la API de APIM para aceptar la clave de suscripción en la cabecera **`x-api-key`**
> (`subscriptionKeyParameterNames.header`), que es la nativa de Anthropic. Así vale
> `ANTHROPIC_API_KEY`; `ANTHROPIC_AUTH_TOKEN` enviaría `Authorization: Bearer …`, que APIM no
> interpreta como clave de suscripción.

Sin contenedor, sin traducción, sin puerto 4000. Todo el tráfico queda gobernado por APIM
(límites, métricas de tokens, identidad keyless) igual que el resto de APIs.

---

## LiteLLM vs. integración directa — cuándo usar cada uno

| Escenario | ¿LiteLLM? | Por qué |
|-----------|-----------|---------|
| Claude Code sobre modelos **OpenAI** (gpt-4.1-mini…) | **Opcional** | Hay que traducir Anthropic ↔ OpenAI, pero puede hacerlo la política de APIM → [Lab 12](12-claude-code-sin-litellm.md) |
| Claude Code sobre **Claude nativo** en Foundry | **No** | Mismo protocolo de punta a punta |
| Cualquier app con SDK de **OpenAI** | **No** | Ya habla OpenAI → directo a APIM |
| GitHub Copilot CLI | **No** | Modelos gestionados por GitHub |

**Guía de decisión:** si el cliente quiere **Claude**, se despliega Claude nativo en Foundry y
Claude Code apunta **directamente** a APIM (este lab). Si quiere reutilizar sus modelos **OpenAI**
desde un cliente Anthropic, la traducción puede vivir en el gateway ([lab 12](12-claude-code-sin-litellm.md))
en lugar de en un LiteLLM que haya que operar; LiteLLM sigue siendo la opción cuando hace falta
*streaming* real token a token o una cartera muy amplia de proveedores.

---

## Siguiente
➡️ [Lab 12 · Claude Code sobre modelos OpenAI, sin LiteLLM](12-claude-code-sin-litellm.md)
