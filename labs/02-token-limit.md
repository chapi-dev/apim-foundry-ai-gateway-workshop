# Lab 02 · Límite de tokens (rate limiting)

## Objetivo
Controlar el consumo de tokens por cliente para proteger coste y capacidad.

## Política
Ya está activa en la API `ai-gateway` (ver `infra/policies/ai-api-policy.xml`):

```xml
<llm-token-limit counter-key="@(context.Subscription.Id)"
    tokens-per-minute="2000"
    estimate-prompt-tokens="false"
    tokens-consumed-header-name="x-tokens-consumed"
    remaining-tokens-header-name="x-tokens-remaining" />
```

- `counter-key`: aísla el límite por clave de suscripción (por equipo/app).
- `tokens-per-minute`: techo de tokens por minuto. También admite `token-quota` por periodo.

## Probar
1. Lanza varias peticiones seguidas (bucle) hasta superar el límite:
   ```powershell
   1..20 | ForEach-Object {
     curl -s -X POST "$env:APIM_GATEWAY_URL/openai/deployments/chat/chat/completions?api-version=2024-10-21" `
       -H "api-key: $env:APIM_SUBSCRIPTION_KEY" -H "Content-Type: application/json" `
       -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Escribe un poema largo\"}],\"max_tokens\":500}' `
       -o /dev/null -w "%{http_code} "
   }
   ```
2. Al superar el límite APIM responde **429 Too Many Requests** con `Retry-After`.

## Ajustar
Cambia `tokens-per-minute` en el editor de políticas del portal
(APIs → `ai-gateway` → Design → All operations → `</>`), o edita el XML y redepliega.

## Siguiente
➡️ [Lab 03 · Métricas y costes](03-metricas-y-costes.md)
