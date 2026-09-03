# Lab 08 · Cliente Claude Code ("cloud code") a través de APIM

## Objetivo
Que **Claude Code** consuma modelos de **Azure AI Foundry** pasando por el gobierno de APIM.

## El reto del protocolo
Claude Code habla el protocolo **Anthropic** (`/v1/messages`). Foundry y APIM hablan
**OpenAI**. Solución: un puente **LiteLLM** que traduce Anthropic → OpenAI y reenvía a APIM.

```
Claude Code ──(Anthropic)──► LiteLLM ──(OpenAI, api-key = clave APIM)──► APIM ──► Foundry
```
Ventaja: **todo el gobierno** (límites, métricas, balanceo, seguridad) se aplica igual que a
cualquier otro cliente.

> **Antes de desplegar nada:** este contenedor **es opcional**. APIM puede hacer esa misma
> traducción en su política, sin pieza intermedia — ver [lab 12](12-claude-code-sin-litellm.md).
> Este lab sigue siendo la opción buena si necesitas *streaming* token a token o modelos de
> proveedores que no están en Foundry (Bedrock, Vertex…). Para todo lo demás, ve al lab 12.

## Pasos

1. **Configurar el puente**
   ```powershell
   cd clients/litellm
   Copy-Item .env.example .env
   # edita .env con APIM_GATEWAY_URL, APIM_SUBSCRIPTION_KEY (de scripts/get-keys.ps1)
   # y un LITELLM_MASTER_KEY a tu elección (p.ej. sk-workshop-1234)
   docker compose up -d
   ```
   LiteLLM queda escuchando en `http://localhost:4000` y expone `/v1/messages` (Anthropic).

2. **Apuntar Claude Code al puente**
   ```powershell
   $env:ANTHROPIC_BASE_URL="http://localhost:4000"
   $env:ANTHROPIC_AUTH_TOKEN="sk-workshop-1234"   # = LITELLM_MASTER_KEY
   claude
   ```
   (equivalente en bash con `export`). Desde ese momento Claude Code envía todo a Foundry vía APIM.

3. **Comprobar el gobierno**
   - Genera tráfico desde Claude Code.
   - Repite el KQL del [Lab 03](03-metricas-y-costes.md): verás los tokens de Claude Code
     contabilizados en Application Insights.
   - Si superas el límite del [Lab 02](02-token-limit.md), Claude Code recibirá errores 429.

## Notas
- `drop_params: true` en `config.yaml` descarta campos Anthropic (p.ej. `thinking`) que la API
  OpenAI no acepta.
- Aquí LiteLLM es un **traductor de protocolo del lado del cliente**, no el gateway: la identidad,
  las cuotas, las métricas y la seguridad se siguen aplicando en APIM. Si surge *"¿y por qué no
  usar LiteLLM como gateway?"*, la respuesta corta es que sería sustituir un PaaS con SLA por un
  proxy que tendrías que operar tú junto con PostgreSQL y Redis.
- Para producción despliega LiteLLM como **Azure Container App** en lugar de local.
- Alternativa nativa: si el cliente usa modelos **Claude reales**, Claude Code puede ir directo;
  aquí el objetivo es **reutilizar los modelos de Foundry** de forma gobernada. Ver [Lab 11](11-claude-en-foundry.md).
- Alternativa **sin contenedor**: la traducción Anthropic ↔ OpenAI también puede hacerla la propia
  política de APIM, con los mismos modelos de este lab. Ver [Lab 12](12-claude-code-sin-litellm.md).

## Siguiente
➡️ [Lab 09 · GitHub Copilot CLI + gh](09-cliente-copilot-cli.md)
