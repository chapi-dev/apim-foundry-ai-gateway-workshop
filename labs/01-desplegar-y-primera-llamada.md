# Lab 01 · Desplegar el AI Gateway y primera llamada

## Objetivo
Desplegar el núcleo y hacer la primera petición gobernada a través de APIM.

## Qué se despliega
- **2x Azure AI Foundry** (Azure OpenAI) con `gpt-4.1-mini` (despliegue `chat`) y, en el
  primero, `text-embedding-3-small` (despliegue `embeddings`).
- **APIM Developer** con la API `ai-gateway` (compatible Azure OpenAI), backend **pool**,
  producto y suscripción de demo.
- **Log Analytics + Application Insights** para métricas.
- **Managed Identity** de APIM con rol *Cognitive Services OpenAI User* sobre ambos Foundry.

## Pasos

1. **Desplegar**
   ```powershell
   ./scripts/deploy.ps1
   ```
   > APIM Developer tarda ~40 min la primera vez. Los recursos de Foundry y monitorización
   > están listos en pocos minutos.

2. **Obtener endpoint y clave**
   ```powershell
   ./scripts/get-keys.ps1
   ```
   Copia `APIM_GATEWAY_URL` y `APIM_SUBSCRIPTION_KEY`.

3. **Primera llamada (Python)**
   ```powershell
   $env:APIM_GATEWAY_URL="https://xxxxx-apim.azure-api.net"
   $env:APIM_SUBSCRIPTION_KEY="<clave>"
   pip install openai
   python clients/test-openai.py
   ```
   O usa `clients/requests.http` con la extensión REST Client de VS Code.

## Qué observar
- La respuesta llega **sin poner ninguna clave de Foundry**: APIM autentica con Managed Identity.
- La cabecera `x-tokens-remaining` muestra el presupuesto de tokens restante.

## Siguiente
➡️ [Lab 02 · Límite de tokens](02-token-limit.md)
