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

> **Usa PowerShell 7** (`pwsh`). En *Windows PowerShell* 5.1 `curl` es un **alias de
> `Invoke-WebRequest`**, así que `-H` falla con *"Cannot bind parameter 'Headers'"*, y además
> los acentos de la respuesta salen mal. Si estás en 5.1, escribe `pwsh` y sigue ahí.
> Los comandos de abajo usan `Invoke-RestMethod`, que funciona en ambas.

**Paso 0 — en cada consola nueva** (las variables no sobreviven a cerrar la ventana):

```powershell
$sub = az account show --query id -o tsv
$env:APIM_GATEWAY_URL      = "https://apim-aigw-dev-01.azure-api.net"
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/rg-aigateway-dev-01/providers/Microsoft.ApiManagement/service/apim-aigw-dev-01/subscriptions/ai-workshop-sub/listSecrets?api-version=2024-06-01-preview" --query primaryKey -o tsv
"KEY = $($env:APIM_SUBSCRIPTION_KEY.Length) caracteres"   # tiene que decir 32
```

> Si ves `URL rejected: No host part in the URL`, es que te saltaste este paso.

1. **Ver el presupuesto consumiéndose** (funciona siempre y es lo mejor para demo):
   ```powershell
   $uri  = "$env:APIM_GATEWAY_URL/openai/deployments/chat/chat/completions?api-version=2024-10-21"
   $hdr  = @{ "api-key" = $env:APIM_SUBSCRIPTION_KEY }
   $body = '{"messages":[{"role":"user","content":"Escribe un poema largo"}],"max_tokens":500}'

   1..6 | ForEach-Object {
     $r = Invoke-WebRequest -Uri $uri -Method Post -Headers $hdr -ContentType "application/json" -Body $body -UseBasicParsing
     "consumidos={0}  restantes={1}" -f ($r.Headers["x-tokens-consumed"] -join ''), ($r.Headers["x-tokens-remaining"] -join '')
   }
   ```
   Verás `restantes` bajando petición a petición: la cuota se está contabilizando.

2. **Forzar el 429.** Con el techo de 2000 TPM cuesta llegar: cada respuesta tarda ~6 s en generar
   ~400 tokens, así que la ventana deslizante de un minuto se renueva antes de acumular el límite
   (lanzarlas en paralelo tampoco basta, porque `estimate-prompt-tokens="false"` solo contabiliza
   **después** de que el modelo responda). Para la demo, baja el techo un momento a `200`:

   ```powershell
   1..8 | ForEach-Object {
     try {
       Invoke-RestMethod -Uri $uri -Method Post -Headers $hdr -ContentType "application/json" -Body $body | Out-Null
       Write-Host -NoNewline "200 "
     } catch {
       Write-Host -NoNewline "$($_.Exception.Response.StatusCode.value__) "
     }
   }
   # con tokens-per-minute="200" ->  200 429 200 429 429 429 429 429
   ```

3. Al superar el límite APIM responde **429 Too Many Requests** con `Retry-After`.

## Ajustar
Cambia `tokens-per-minute` en el editor de políticas del portal
(APIs → `ai-gateway` → **Design** → *All operations* → **`</>`**), o edita
`infra/policies/ai-api-policy.xml` y redespliega. **Acuérdate de devolverlo a `2000`**
después de la demo.

## Siguiente
➡️ [Lab 03 · Métricas y costes](03-metricas-y-costes.md)
