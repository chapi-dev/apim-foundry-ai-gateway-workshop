# Lab 04 · Balanceo de carga y failover

## Objetivo
Repartir el tráfico entre varios despliegues de Foundry y tolerar fallos automáticamente.

## Cómo está montado
`infra/modules/apim.bicep` crea:
- Un **backend individual** por cada Foundry (`aoai-0`, `aoai-1`) con **circuit breaker**
  (abre 30 s tras 3 respuestas 429/5xx).
- Un **backend pool** `aoai-pool` con ambos (peso y prioridad configurables).

La política enruta al pool:
```xml
<set-backend-service backend-id="aoai-pool" />
```

## Estrategias
- **Round-robin ponderado**: mismo `priority`, distintos `weight`.
- **Activo/pasivo (failover)**: distinta `priority` (menor = preferente). El pool solo usa el
  secundario si el primario está en circuito abierto.

Edita el pool en `apim.bicep` (`priority`/`weight`) y redepliega, o hazlo en el portal
(APIs → Backends).

## Probar el failover
1. Provoca 429 saturando `aoai-0` (o deshabilita temporalmente su despliegue en Foundry).
2. Observa que las siguientes peticiones siguen respondiendo (van a `aoai-1`).
3. La cabecera `x-backend-url` (añadida en la política) ayuda a ver la ruta.

## Nota de producción
Combina el pool con reintentos (`<retry>`) y con despliegues en **varias regiones** para
alta disponibilidad real.

## Siguiente
➡️ [Lab 05 · Semantic cache](05-semantic-cache.md)
