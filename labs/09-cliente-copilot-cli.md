# Lab 09 · GitHub Copilot CLI y `gh`

## Objetivo
Presentar la vía **nativa de GitHub** para desarrolladores en terminal, y situarla frente al
AI Gateway.

## GitHub Copilot CLI
```powershell
# Instalar (extensión de gh)
gh extension install github/gh-copilot

# Sugerencias y explicación de comandos
gh copilot suggest "comprimir una carpeta en tar.gz"
gh copilot explain "az apim show -g rg -n apim --query identity"
```
También existe el nuevo **Copilot CLI** independiente (`copilot`) para tareas de agente en el
terminal.

## Dónde encaja
- **Copilot** usa los modelos gestionados por GitHub (no tus despliegues de Foundry). Es la
  opción llave en mano si el cliente ya vive en GitHub: cero infraestructura, gobierno vía
  políticas de organización de Copilot.
- **APIM + Foundry** es la opción cuando el cliente necesita **sus propios modelos**, control de
  datos/región, **coste por equipo** y políticas propias (límites, caché, seguridad).

Ambas son complementarias: Copilot para productividad del desarrollador, APIM+Foundry para las
**cargas de la aplicación** y el gobierno corporativo del consumo de modelos.

## `gh` para el workshop
```powershell
gh repo create apim-foundry-workshop --public --source . --push
gh workflow list        # si añades CI/CD de las políticas (APIOps)
```

## Idea de demo combinada
Usa `gh` para desplegar el repo y un **GitHub Actions** que publique las políticas de APIM
(enfoque *policy-as-code* / APIOps) en cada push.

## Siguiente
➡️ [Lab 10 · Gobierno de MCP](10-mcp.md)
