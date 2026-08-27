# Lab 07 · Managed Identity (keyless)

## Objetivo
Eliminar las claves de Foundry del cliente y de las políticas: APIM se autentica con su
**identidad administrada**.

## Cómo funciona
`infra/main.bicep` asigna a la Managed Identity de APIM el rol **Cognitive Services OpenAI User**
sobre ambos Foundry. La política obtiene un token de Entra ID y lo inyecta:

```xml
<authentication-managed-identity resource="https://cognitiveservices.azure.com"
    output-token-variable-name="msi-access-token" />
<set-header name="Authorization" exists-action="override">
    <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
</set-header>
```

## Verificar
```powershell
# Ver la identidad de APIM
az apim show -g rg-apim-workshop -n <apim> --query identity

# Ver las asignaciones de rol sobre un Foundry
az role assignment list --scope $(az cognitiveservices account show -g rg-apim-workshop -n <foundry1> --query id -o tsv) -o table
```

El cliente solo usa la **clave de suscripción de APIM** (cabecera `api-key`); nunca ve las
claves de Foundry. Puedes incluso desactivar `disableLocalAuth` en Foundry para forzar
Entra-only.

## Siguiente
➡️ [Lab 08 · Cliente Claude Code](08-cliente-claude-code.md)
