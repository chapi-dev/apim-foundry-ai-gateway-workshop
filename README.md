# APIM + Azure AI Foundry — Workshop de AI Gateway

Workshop práctico para presentar a un cliente **todas las opciones** de consumir modelos de
**Azure AI Foundry** de forma gobernada usando **Azure API Management (APIM) como AI Gateway**
(la arquitectura de referencia de Microsoft para GenAI).

El hilo conductor: los desarrolladores usan **su herramienta preferida** (Claude Code "cloud
code", GitHub Copilot CLI, o cualquier SDK OpenAI) pero **todo el tráfico pasa por APIM**, que
aplica límites de tokens, métricas de coste, balanceo, caché semántica, seguridad de contenido
e identidad administrada — sin claves en el cliente.

---

## 🗺️ Arquitectura

```
  GitHub Copilot CLI / gh ─(OpenAI)─┐
  OpenAI SDK (Python/Node) ─(OpenAI)─┤
                                     ├──► APIM  ──(Managed Identity, keyless)──►  Azure AI Foundry
  Claude Code ─(Anthropic)─► LiteLLM ┘     │                                       ├─ chat  (gpt-4.1-mini) x2 backends
                             (traduce)      │                                       └─ embeddings (text-embedding-3-small)
                                            │
                                   Application Insights  ◄─ métricas de tokens/coste
                                   Azure Managed Redis   ◄─ semantic cache
                                   Azure AI Content Safety ◄─ jailbreak / prompt shield
```

Todos los clientes convergen en el **mismo endpoint compatible con Azure OpenAI** expuesto por
APIM. Claude Code habla protocolo Anthropic, así que usa **LiteLLM** como puente que traduce a
OpenAI y reenvía a APIM.

---

## 🍽️ Menú de opciones (lo que puedes enseñar al cliente)

### A. Herramienta del desarrollador (cómo consumen los modelos)
| Opción | Protocolo | Ruta | Lab |
|--------|-----------|------|-----|
| **Claude Code** ("cloud code") | Anthropic | Claude Code → LiteLLM → APIM → Foundry | [08](labs/08-cliente-claude-code.md) |
| **GitHub Copilot CLI + `gh`** | — | Copilot nativo + `gh copilot` en terminal | [09](labs/09-cliente-copilot-cli.md) |
| **OpenAI SDK genérico** | OpenAI | App → APIM → Foundry | [01](labs/01-desplegar-y-primera-llamada.md) |
| **Foundry directo** (línea base) | OpenAI | App → Foundry (sin gobierno) | comparativa |

### B. APIM como AI Gateway (el núcleo)
| Módulo | Política | Lab |
|--------|----------|-----|
| Límite de tokens / rate limiting | `llm-token-limit` | [02](labs/02-token-limit.md) |
| Métricas de tokens y **coste** | `llm-emit-token-metric` → App Insights | [03](labs/03-metricas-y-costes.md) |
| Balanceo de carga / failover | backend **pool** + circuit breaker | [04](labs/04-balanceo-y-failover.md) |
| Caché semántica | `azure-openai-semantic-cache-*` + Redis | [05](labs/05-semantic-cache.md) |
| Content safety / jailbreak | `llm-content-safety` (prompt shields) | [06](labs/06-content-safety.md) |
| Managed Identity (keyless) | `authentication-managed-identity` | [07](labs/07-managed-identity.md) |
| Gobierno de **MCP** | exponer/gobernar servidores MCP | [10](labs/10-mcp.md) |

---

## ✅ Requisitos previos

- Suscripción de Azure con permisos de Colaborador + capacidad de asignar roles.
- [Azure CLI](https://learn.microsoft.com/cli/azure/) con la extensión Bicep (`az bicep version`).
- [GitHub CLI](https://cli.github.com/) (`gh auth status`).
- [Docker](https://www.docker.com/) (para el puente LiteLLM de Claude Code).
- Python 3.10+ (para los scripts de prueba).

---

## 🚀 Quickstart

```powershell
# 1. Desplegar el núcleo (Foundry x2 + APIM Developer + monitorización)
./scripts/deploy.ps1                 # APIM Developer tarda ~40 min

# 2. Obtener endpoint y clave
./scripts/get-keys.ps1

# 3. Primera llamada gobernada
$env:APIM_GATEWAY_URL="https://xxxxx-apim.azure-api.net"
$env:APIM_SUBSCRIPTION_KEY="<clave>"
pip install openai
python clients/test-openai.py
```

Después, sigue los [labs](labs/) en orden.

---

## 💸 Coste (orientativo, Sweden Central)

| Recurso | SKU | Coste aprox. |
|---------|-----|--------------|
| APIM | **Developer** | ~40–50 €/mes (sin SLA; el más barato con políticas LLM) |
| Azure AI Foundry (2x) | pago por token | solo lo que consumas en la demo |
| Log Analytics + App Insights | pago por ingesta | céntimos en una demo |
| Azure Managed Redis (lab 05) | Balanced B0 | por horas — despliega solo durante el lab |
| Content Safety (lab 06) | F0/S0 | F0 gratis con límites |

> **Developer** es el SKU más barato que soporta todas las políticas LLM del workshop
> (incluida la caché semántica). Para producción usa **BasicV2/StandardV2/PremiumV2**
> (SLA, VNet, autoescalado). Cambia el SKU con `./scripts/deploy.ps1 -ApimSku StandardV2`.

Al terminar: `./scripts/cleanup.ps1` elimina todo.

---

## 📁 Estructura

```
infra/        Bicep del núcleo + políticas XML (aplicadas y snippets de labs)
labs/         Guías paso a paso (00 → 10)
clients/      LiteLLM (Claude Code), pruebas OpenAI SDK / HTTP
scripts/      deploy / get-keys / cleanup
```
