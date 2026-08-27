# Lab 10 · Gobierno de MCP con APIM

## Objetivo
Mostrar cómo APIM gobierna y expone **servidores MCP** (Model Context Protocol), la forma en que
Claude Code, Copilot y los agentes descubren y usan herramientas.

## Dos escenarios

### A. Exponer una API REST existente como servidor MCP
APIM puede **convertir una API en un servidor MCP**, publicando sus operaciones como *tools*
consumibles por clientes MCP.
- Portal → tu APIM → **APIs** → selecciona una API → **... → Export / Create MCP server**
  (o *MCP Servers* → *Create*), elige las operaciones a exponer como herramientas.
- Aplica políticas al servidor MCP: **rate limiting**, autenticación, `llm-token-limit`,
  logging — el mismo modelo de gobierno que a cualquier API.

### B. Gobernar un servidor MCP existente (pass-through)
Publica un MCP de terceros detrás de APIM para añadir autenticación, cuotas y observabilidad
centralizadas antes de exponerlo a los desarrolladores.

## Conectar un cliente
- **Claude Code**: añade el servidor MCP (`claude mcp add`) apuntando a la URL de APIM.
- **Copilot / VS Code**: configura el MCP server en `mcp.json` con la URL de APIM y la clave.

## Por qué importa al cliente
- Un **único punto** para descubrir, asegurar y medir el uso de herramientas MCP.
- Rate limiting y auth por equipo sobre las herramientas, no solo sobre los modelos.

## Referencias
- APIM + MCP: https://learn.microsoft.com/azure/api-management/export-rest-mcp-server
- AI Gateway capabilities: https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities

## Fin del workshop 🎉
Vuelve al [README](../README.md) para el menú completo. Recuerda `./scripts/cleanup.ps1`.
