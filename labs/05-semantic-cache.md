# Lab 05 · Caché semántica

## Objetivo
Devolver respuestas cacheadas para prompts **iguales o semánticamente similares**, reduciendo
tokens, coste y latencia.

## Requisitos
1. **Backend de embeddings** en APIM apuntando al despliegue `embeddings` del primer Foundry.
2. **Caché externa con búsqueda vectorial**: **Azure Managed Redis** (SKU Balanced B0, el más
   barato con vector search).

## Pasos

### 1. Desplegar Azure Managed Redis (solo durante este lab)
```powershell
az redisenterprise create -g rg-apim-workshop -n aigw-redis -l swedencentral --sku Balanced_B0
```
> Recuerda borrarlo al terminar el lab para no acumular coste por horas.

### 2. Conectar Redis como caché externa de APIM
Portal → tu APIM → **External cache** → *Add* → selecciona el Redis, `Use from = Default`.

### 3. Crear el backend de embeddings
Portal → APIM → **Backends** → *Add*:
- Nombre: `embeddings-backend`
- URL: `https://<foundry1>.openai.azure.com/openai/deployments/embeddings`
- Autenticación: Managed Identity (recurso `https://cognitiveservices.azure.com`).

### 4. Añadir la política
Inserta el contenido de `infra/policies/snippets/05-semantic-cache.xml` en la política de la
API `ai-gateway` (`azure-openai-semantic-cache-lookup` en inbound, `-store` en outbound).

## Probar
Lanza dos veces prompts parecidos ("¿Qué es un AI Gateway?" y "Explícame qué es un AI gateway").
La segunda debería resolverse desde caché (latencia mucho menor, `TotalTokens` ≈ 0 en métricas).

## Siguiente
➡️ [Lab 06 · Content safety](06-content-safety.md)
