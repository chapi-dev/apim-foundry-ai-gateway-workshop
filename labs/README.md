# 🧪 Labs — el recorrido completo

El [README raíz](../README.md) agrupa los labs **por tema** (qué enseñar al cliente). Esta página
los ordena **como se hacen**, del 00 al 13.

No hace falta hacerlos todos: el **núcleo** (00 → 04, 07) monta y justifica el gateway; el resto
son piezas que se añaden según lo que le interese al cliente.

---

## Núcleo — el gateway y su gobierno

| Lab | Qué monta | Requiere aparte |
|-----|-----------|-----------------|
| [00 · Preparación](00-setup.md) | Deja tu equipo listo: Azure CLI, sesión, suscripción | — |
| [01 · Desplegar y primera llamada](01-desplegar-y-primera-llamada.md) | 2× Foundry + APIM + monitorización, y la primera petición gobernada | — |
| [02 · Límite de tokens](02-token-limit.md) | `llm-token-limit`: cuota por cliente, y el `429` con `Retry-After` | — |
| [03 · Métricas y costes](03-metricas-y-costes.md) | `llm-emit-token-metric` → Application Insights: tokens y coste por equipo | — |
| [04 · Balanceo y failover](04-balanceo-y-failover.md) | Backend **pool** con *circuit breaker* entre los dos Foundry | — |
| [07 · Managed Identity](07-managed-identity.md) | Keyless de verdad: ni el cliente ni el gateway guardan claves de Foundry | — |

## Extras de gobierno

| Lab | Qué monta | Requiere aparte |
|-----|-----------|-----------------|
| [05 · Caché semántica](05-semantic-cache.md) | Respuestas cacheadas para prompts **similares**, no solo idénticos | Azure Managed Redis |
| [06 · Content safety](06-content-safety.md) | Filtrado de contenido y *prompt shields* **antes** del modelo | Azure AI Content Safety |
| [10 · Gobierno de MCP](10-mcp.md) | Exponer y gobernar servidores MCP para agentes | — |

## Clientes — cómo consumen los desarrolladores

| Lab | Qué monta | Requiere aparte |
|-----|-----------|-----------------|
| [08 · Claude Code con LiteLLM](08-cliente-claude-code.md) | El puente clásico en contenedor (la opción a batir) | Docker |
| [09 · GitHub Copilot CLI y `gh`](09-cliente-copilot-cli.md) | La vía nativa de GitHub, situada frente al gateway | GitHub CLI |
| [11 · Claude nativo en Foundry](11-claude-en-foundry.md) | Claude Code contra un modelo **Claude** real, sin traducir nada | Modelo Claude en Foundry |
| [12 · Claude Code sin LiteLLM](12-claude-code-sin-litellm.md) ⭐ | La traducción Anthropic ↔ OpenAI **dentro de la política de APIM**: cero contenedores | — |

## Alternativa moderna

| Lab | Qué monta | Requiere aparte |
|-----|-----------|-----------------|
| [13 · El SKU AI Gateway (preview)](13-ai-gateway-tier.md) | El mismo gobierno **sin XML**: modelos, MCP, políticas y trazas como configuración | Feature flag + East US 2 o Sweden Central |

---

## 🎬 Para presentar

| Guión | Cuándo usarlo |
|-------|---------------|
| [`DEMO.md`](DEMO.md) | Demo por **consola**, con comandos copy-paste. |
| [`DEMO-portal.md`](DEMO-portal.md) | Demo **solo con el portal**, sin tocar PowerShell. Incluye un acto opcional del SKU AI Gateway. |

Las capturas que usan estas guías están en [`img/`](img/) y son reales, tomadas del entorno del
workshop y anonimizadas.
