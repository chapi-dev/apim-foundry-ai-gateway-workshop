# 🖱️ Guión de demo · sólo Portal (sin consola)

Misma historia que [DEMO.md](DEMO.md), pero **todo desde el portal de Azure**. Sirve cuando
presentas compartiendo pantalla y no quieres pelearte con PowerShell, o cuando el cliente quiere
ver *dónde vive* cada cosa.

Duración ~25 min. Formato de cada acto: **dónde clicar → qué enseñar → qué decir**.

---

## Preparación (antes de compartir pantalla)

Deja abiertas estas pestañas:

| # | Pestaña | Ruta |
|---|---------|------|
| 1 | APIM | `rg-aigateway-dev-01` → **apim-aigw-dev-01** |
| 2 | Application Insights | `rg-aigateway-dev-01` → **appi-aigw-dev-01** |
| 3 | Foundry | `rg-apim-workshop` → **aigwqyxvxaoai1** |

> Comprueba antes que `llm-token-limit` está en **2000** (Acto 3 lo baja y lo devuelve).

**Frase de apertura:** *"Todo lo que veréis pasa por un único punto gobernado —APIM como AI
Gateway— delante de Azure AI Foundry. El desarrollador usa su herramienta favorita; la empresa
mantiene control de coste, seguridad e identidad."*

---

## Acto 1 · El mapa (2 min)

**Dónde:** `rg-aigateway-dev-01` → **Overview**.

**Enseñar:** son sólo tres piezas — `apim-aigw-dev-01` (el gateway), `appi-aigw-dev-01`
(telemetría) y `log-aigw-dev-01` (Log Analytics). Los modelos viven aparte, en
`rg-apim-workshop`.

**Decir:** *"El gateway es una capa fina. Vuestros modelos, vuestra región, vuestro coste — no se
mueven. Lo que añadimos es la puerta de entrada."*

---

## Acto 2 · Primera llamada gobernada (4 min)

**Dónde:** APIM → **APIs** → **AI Gateway (Foundry)** → pestaña **Test** → **Chat completions**.

**Rellenar:**

| Campo | Valor |
|-------|-------|
| Template parameter `deployment` | `chat` |
| Template parameter `api-version` | `2024-10-21` |
| Headers → `Content-Type` | `application/json` |
| Body → *Raw* | `{"messages":[{"role":"user","content":"Explica un AI Gateway en una frase"}]}` |

Pulsa **Send**.

**Enseñar:** la respuesta 200, y sobre todo la pestaña **HTTP request**: el portal mete solo la
cabecera `api-key` con la clave de la suscripción `ai-workshop-sub`. Ninguna clave de Foundry.

**Decir:** *"El cliente sólo tiene la clave de APIM. Rotar credenciales de Foundry o cambiar de
modelo no le afecta."*

---

## Acto 3 · Keyless de verdad: Managed Identity (3 min)

**Dónde (1):** APIM → **Managed identities** → *System assigned* = **On**.

**Dónde (2):** pestaña del Foundry → **Access control (IAM)** → **Role assignments** → filtra por
`apim`. Verás la identidad de APIM con el rol **Cognitive Services OpenAI User**.

**Dónde (3):** APIM → **APIs** → *AI Gateway (Foundry)* → **Design** → *All operations* →
en **Inbound processing** pulsa **`</>`**. Enseña la primera política:

```xml
<authentication-managed-identity resource="https://cognitiveservices.azure.com"
    output-token-variable-name="msi-access-token" />
```

**Decir:** *"No hay ninguna clave de Foundry en ningún sitio: ni en el cliente, ni en el gateway.
APIM pide un token con su identidad. Esto es lo que suele desbloquear al equipo de seguridad."*
→ lab 07.

---

## Acto 4 · Límite de tokens y el 429 (5 min) — el mejor acto en portal

**Dónde:** el mismo editor `</>` del acto anterior. Enseña:

```xml
<llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="2000" ... />
```

**Paso 1 — la cuota se contabiliza.** Vuelve a **Test** → **Send** un par de veces y mira la
pestaña **HTTP response**: las cabeceras `x-tokens-consumed` y `x-tokens-remaining` van bajando.

**Paso 2 — provocar el 429.** En el editor `</>`, cambia `tokens-per-minute` a **`200`** y pulsa
**Save**. Vuelve a **Test** y pulsa **Send** 3-4 veces: a la segunda ya sale
**429 Too Many Requests** con `Retry-After`.

> ⚠️ **Devuelve el valor a `2000` y pulsa Save** antes de seguir.
> Con 2000 el 429 no llega a saltar en directo: cada respuesta tarda ~6 s en generar ~400 tokens
> y la ventana de un minuto se renueva antes de acumular el límite.

**Decir:** *"Cuota por clave, es decir por equipo o por aplicación. Y fijaos en que el cambio ha
sido inmediato, sin tocar el cliente ni redesplegar nada."* → lab 02.

---

## Acto 5 · Balanceo y failover (3 min)

**Dónde:** APIM → **Backends** (menú izquierdo, sección *APIs*).

**Enseñar:** `aoai-pool` es un **pool** con dos miembros, `aoai-0` y `aoai-1`, que apuntan a los
dos Foundry (`aigwqyxvxaoai1` y `aigwqyxvxaoai2`). Abre uno y enseña el **circuit breaker**.
Vuelve al editor `</>` y señala la última línea: `<set-backend-service backend-id="aoai-pool" />`.

**Decir:** *"Si un despliegue devuelve 429 o 5xx, el breaker lo saca 30 segundos y el tráfico
sigue por el otro. Es la base para multi-región y para repartir cuota entre despliegues."* → lab 04.

---

## Acto 6 · Métricas de tokens y coste (4 min)

**Dónde (1):** APIM → **Metrics** → métrica *Requests*, split por *Response code*. Es la vista
operativa de siempre.

**Dónde (2):** pestaña de **appi-aigw-dev-01** → **Logs** → pega el KQL:

```kusto
customMetrics
| where name in ("TotalTokens","PromptTokens","CompletionTokens")
| extend sub = tostring(customDimensions["Subscription ID"]),
         deploy = tostring(customDimensions["Deployment"])
| summarize tokens = sum(valueSum) by name, deploy, bin(timestamp, 5m)
| order by timestamp desc
```

**Decir:** *"Cada llamada emite tokens de prompt y de completion con dimensiones. Multiplicando
por el precio del modelo tenéis FinOps por equipo, sin instrumentar ni una línea de vuestras
apps."* → lab 03.

> Las métricas tardan 2-5 min en ingestar. Genera tráfico en el Acto 2 y ten una captura de
> respaldo por si acaso.

---

## Acto 7 · Quién puede llamar (2 min)

**Dónde:** APIM → **Subscriptions** y → **Products**.

**Enseñar:** el producto `ai-workshop` y su suscripción `ai-workshop-sub`. Desde aquí se
regeneran claves, se suspende un consumidor o se crea una suscripción nueva por equipo — y el
`counter-key` de la política hace que cada una tenga **su propia cuota**.

**Decir:** *"Dar de alta a un equipo nuevo es crear una suscripción. Cortarle el grifo es un
clic."*

---

## Acto 8 · Claude Code sobre vuestros modelos (5 min)

Este es el único que necesita una consola, y es un solo comando. Ten la ventana **ya preparada y
con las variables puestas** antes de compartir pantalla (ver [DEMO.md](DEMO.md), acto 0).

**Antes**, en el portal: APIM → **APIs** → **Anthropic bridge (Claude Code → Foundry)** →
**Design** → `</>`. Enseña que la traducción de protocolo vive **en la política**.

**Decir:** *"Claude Code habla Anthropic, vuestros modelos hablan OpenAI. La traducción la hace el
gateway: cero contenedores, cero piezas que operar. Y hereda el mismo límite, las mismas métricas
y la misma identidad que acabáis de ver."* → lab 12.

Luego cambia a la consola y lanza `claude`. Pide algo del repo para que se vea el ciclo agéntico.

> El texto sale de golpe, no palabra a palabra: el streaming del puente es sintético. Dilo tú
> antes de que lo pregunten.

---

## Cierre (1 min)

Vuelve a la pestaña del APIM, a la lista de **APIs**.

*"Una sola puerta. Cualquier herramienta de desarrollo, cualquier modelo de Foundry, con límites,
coste, seguridad e identidad centralizados. Y todo lo que habéis visto está en Bicep en el repo,
aplicable sobre vuestro APIM existente."*
