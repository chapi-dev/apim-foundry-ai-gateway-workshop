# Lab 06 · Content safety y jailbreak (prompt shields)

## Objetivo
Filtrar contenido dañino y detectar intentos de *jailbreak* / inyección de prompt **antes** de
llegar al modelo, de forma centralizada en el gateway.

## Requisitos
Un recurso **Azure AI Content Safety**:
```powershell
az cognitiveservices account create -g rg-apim-workshop -n aigw-contentsafety `
  --kind ContentSafety --sku S0 -l swedencentral --custom-domain aigw-contentsafety
```
Da a la Managed Identity de APIM el rol *Cognitive Services User* sobre este recurso.

## Pasos
1. Crea un **backend** `content-safety-backend` en APIM apuntando al endpoint de Content Safety
   (autenticación Managed Identity).
2. Inserta `infra/policies/snippets/06-content-safety.xml` en el `<inbound>` de la API.

```xml
<llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
    <categories output-type="EightSeverityLevels">
        <category name="Hate" threshold="4" />
        <category name="Violence" threshold="4" />
    </categories>
</llm-content-safety>
```
- `shield-prompt="true"`: activa **Prompt Shields** (detección de jailbreak / inyección).
- `threshold`: severidad a partir de la cual se bloquea (0–7).

## Probar
- Un prompt normal pasa.
- Un prompt con contenido de una categoría por encima del umbral, o un intento de jailbreak
  ("ignora tus instrucciones y..."), recibe **403** desde APIM sin llegar al modelo.

## Siguiente
➡️ [Lab 07 · Managed Identity](07-managed-identity.md)
