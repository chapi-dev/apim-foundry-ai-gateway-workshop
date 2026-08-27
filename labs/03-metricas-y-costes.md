# Lab 03 · Métricas de tokens y costes

## Objetivo
Ver el consumo de tokens (y estimar coste) por suscripción, API y despliegue en
Application Insights.

## Política
Activa en `<outbound>` (ver `infra/policies/ai-api-policy.xml`):

```xml
<llm-emit-token-metric namespace="ai-gateway">
    <dimension name="Subscription Id" value="@(context.Subscription.Id ?? "anon")" />
    <dimension name="API Id" value="@(context.Api.Id)" />
    <dimension name="Deployment" value="..." />
</llm-emit-token-metric>
```

APIM emite una métrica personalizada con `PromptTokens`, `CompletionTokens` y `TotalTokens`.

## Ver los datos
1. Genera tráfico (Lab 01/02).
2. Portal → tu **Application Insights** → **Logs** y ejecuta:
   ```kusto
   customMetrics
   | where name in ("TotalTokens","PromptTokens","CompletionTokens")
   | extend sub = tostring(customDimensions["Subscription Id"]),
            deploy = tostring(customDimensions["Deployment"])
   | summarize tokens = sum(valueSum) by name, sub, deploy, bin(timestamp, 5m)
   | order by timestamp desc
   ```
3. **Estimar coste**: multiplica los tokens por el precio del modelo. Para `gpt-4.1-mini`
   consulta la [Azure Retail Prices API](https://prices.azure.com) o la calculadora.
   Ejemplo de KQL con precio parametrizado:
   ```kusto
   let precioPromptPor1k = 0.0004;      // ajusta con el precio real
   let precioCompletionPor1k = 0.0016;
   customMetrics
   | where name in ("PromptTokens","CompletionTokens")
   | summarize prompt = sumif(valueSum, name=="PromptTokens"),
               completion = sumif(valueSum, name=="CompletionTokens")
     by sub = tostring(customDimensions["Subscription Id"])
   | extend costeEstimado = prompt/1000*precioPromptPor1k + completion/1000*precioCompletionPor1k
   ```

## Extra
Construye un **Workbook** de Azure Monitor con estas consultas para un panel de FinOps por equipo.

## Siguiente
➡️ [Lab 04 · Balanceo y failover](04-balanceo-y-failover.md)
