# Pendientes

Estado real de la migración a `dbt_ahorrazo`, para que cualquier
conversación/persona pueda retomar sin releer todo el historial. Ver
`../PLAN_MAESTRO_REINGENIERIA.md` para el plan completo por fases y la
sección "Estado de ejecución" ahí para el resumen a nivel portfolio.

## Para retomar ahora mismo

1. Correr (si no se hizo ya): `dbt build --select +top300_ranking` --
   se acaba de corregir un bug real de tipos (ver "Top 300" abajo), no
   se confirmó todavía que pase con el fix aplicado.
2. Correr: `dbt show --select validar_clientes_mapeo_limpio --limit 20`
   -- Fase 2 ya está construida y testeada, pero la comparación contra
   el legacy TODAVÍA NO SE CORRIÓ. Es el paso que falta para poder
   repuntar `stg_clientes_mapeo`/`stg_clientes_limpio` al proceso nuevo.
3. Entorno: `cd dbt_ahorrazo && source activar.sh` antes de cualquier
   comando dbt (activa venv Python 3.12, carga `.env`, apunta
   `DBT_PROFILES_DIR` a esta carpeta). Ver `COMANDOS.md` para la
   referencia completa de comandos y selectors.
4. **Convención de esta sesión**: decir qué comando correr, no correrlo
   uno mismo salvo que se pida explícitamente -- el usuario quiere
   ejecutar y entender cada paso.
5. **No mencionar IA/Claude en mensajes de commit** -- preferencia
   explícita del usuario.

---

## Fase 1 — Fundación — CONFIRMADA contra la base real
`stg_ventas`, `stg_productos`, `stg_clientes_mapeo`, `stg_clientes_limpio`,
`stg_clientes`, `fct_ventas_36m`, seed `dim_sucursal_mapeo`. `dbt debug`
funciona (requirió `trust_cert: true` en el profile -- el server usa
certificado autofirmado, hallazgo nuevo no documentado en el plan
maestro original).

## Fase 2 — `clientes_mapeo_limpio` — CONSTRUIDO, VALIDACIÓN PENDIENTE

- [x] `int_clientes_normalizados`, `int_clientes_mapeo_limpio`
  (incremental), `int_clientes_limpio` (`table`) -- construidos y
  testeados contra la base real (`dbt build ... --full-refresh`, 10/10
  PASS, incluye `assert_cliente_id_limpio_no_explota`).
- [x] Perfilado de calidad real corrido (`analyses/perfilar_calidad_cliente_id.sql`):
  800.930 ids totales, 19 con caracteres no contemplados, 32 que
  quedaban vacíos tras limpiar. **Ambos casos ya se investigaron y se
  corrigieron** (ver "Bugs encontrados y corregidos" abajo).
- [ ] **`analyses/validar_clientes_mapeo_limpio.sql` -- NO CORRIDO
  TODAVÍA.** Es el paso que falta:
  - `conteo_solo_nuevo` **tiene que dar 0** (si no, hay un bug real).
  - `conteo_valor_distinto` / `conteo_solo_legacy` > 0 es esperado --
    confirmar (sección 2 del archivo) que encajan en los patrones ya
    identificados (símbolos en los extremos, separador raro + 1 dígito,
    clientes no identificables excluidos) y no algo nuevo.
- [ ] **Recién después de validar**: repuntar `stg_clientes_mapeo`/
  `stg_clientes_limpio` de sus `source()` actuales a
  `ref('int_clientes_mapeo_limpio')`/`ref('int_clientes_limpio')`.
- **No usar `int_clientes_mapeo_limpio`/`int_clientes_limpio` desde
  ningún mart nuevo hasta validar esto.**
- Nota de performance real observada: el full-refresh de
  `int_clientes_mapeo_limpio` tardó 47 min la primera corrida y 67 min
  la segunda (mismo código) -- variabilidad de carga del server, no un
  problema del modelo. Corridas incrementales normales deberían ser
  mucho más rápidas (solo escanean la ventana de lookback de 45 días).

## Fase 3 — `int_ventas_elegibles` — CONFIRMADA
Unifica las 3 reglas de exclusión (empresa, categoría, cliente test,
producto excluido -- seed `productos_excluidos.csv`, lista real sacada
de `top_300_productos.ipynb`). `dbt build --select +int_ventas_elegibles`
-- 13/13 PASS.

También en esta capa: **`int_ventas_12m`** (ventana móvil de 12 meses,
COMPARTIDA entre Top 300 y Mayoristas -- ver "Decisiones de arquitectura
tomadas en el camino" abajo).

- [ ] Limpieza opcional, no bloqueante: migrar `fct_ventas_36m` para que
  use `ref('int_ventas_elegibles')` en vez de su copia inline de las
  mismas reglas.

## Fase 4 — Marts por proyecto

### Canibalización — CONFIRMADA contra la base real (con fix de ventana ya re-testeado)
- [x] `fct_ventas_36m` -- re-testeado después del fix de meses cerrados
  (`dbt build --select fct_ventas_36m --full-refresh`, OK).
- [x] `fct_ventas_36m_pivotado` -- construido y testeado.
- [x] `dim_cliente_tipo_migracion` -- construido y testeado (8/8 PASS,
  incluye `accepted_values` con los 16 `tipo_cliente` reales).
  **DECISIÓN QUE NECESITA CONFIRMACIÓN DE NEGOCIO ANTES DE FASE 6**:
  el legacy (`_conditions()` en `canibalizacion_v1_usado.ipynb`) tiene
  un bug real -- la categoría "Cliente SL, R1 y R2" chequea
  `R1_acumulado` dos veces y nunca `SL_acumulado`, así que cualquier
  cliente con actividad en R1+R2 (sin SL) queda mal etiquetado como
  "SL, R1 y R2" en vez de "Dual R1 y R2" (evidencia: en el
  `value_counts()` real del notebook, "SL, R1 y R2" = 463.626 casos vs.
  "Dual R1 y R2" = apenas 1.302 -- desproporción que cuadra con el bug).
  Se portó la versión CORREGIDA. Efecto: al comparar contra el legacy,
  NO va a coincidir 1:1 en esas dos categorías puntuales (sí debería
  coincidir la suma de ambas). **Confirmar con el equipo de negocio que
  corregir esto es lo que quieren antes de cortar a producción.**

### Top 300 — CÓDIGO LISTO, ÚLTIMO FIX SIN CONFIRMAR CONTRA LA BASE
- [x] `int_top300_kpis` + `top300_ranking` -- lógica leída del notebook
  real (`ranking_metricas_2025`, `construir_top300_con_metricas`,
  `_normalizar_logaritmica_0_100`): KPIs, normalización log 0-100 (pesos
  0.40/0.30/0.20/0.10, umbral 5.000.000 Gs -- ya en `dbt_project.yml`),
  buckets de unidades por ticket.
- [x] Corregido error 4109 (SQL Server no permite `OVER()` anidado
  dentro de otro `OVER()`) -- normalización separada en etapas explícitas.
- [x] Extraído `int_ventas_12m` compartido (ver abajo) en vez de que Top
  300 calculara su propia ventana.
- [x] Corregido error 245/248 (`producto_id` no es puramente numérico
  en la base real -- valores como `"1685-G"` y `"7506295378"` que
  desbordan `int`). `producto_id` casteado a `varchar(100)` en
  `stg_ventas`/`stg_productos`, seed `productos_excluidos` forzado a
  `varchar(50)` vía `column_types`.
- [ ] **Pendiente confirmar**: `dbt build --select +top300_ranking` con
  el fix de tipos ya aplicado -- el último intento fue ANTES de este
  fix y falló. No se sabe si hay más errores de tipo/lógica más allá de
  este.
- [ ] Pendiente, no bloqueante: enriquecer con metadata de producto
  (nombre/categoria/precio desde `dbo.Productos`) -- el notebook lo hace
  en una celda aparte al final, no portado todavía.

### Mayoristas — NO INICIADA
- [ ] Todo pendiente (`fct_features_cliente_*`, `clasificar_nivel()`
  portado a módulo Python testeado). `int_ventas_12m` (ver arriba) ya
  está listo para que Mayoristas lo reutilice directamente -- no
  duplicar el filtro de ventana ahí.

---

## Bugs encontrados y corregidos durante la migración (no en el plan original)

1. **`clientes_mapeo_limpio.sql` (legacy)**: prometía en un comentario
   "quita el caracter '|'" pero el código nunca lo hacía. Corregido de
   forma general (no solo para `|`): cualquier símbolo suelto al
   principio/final de un id se saca (`recortar_basura_extremos`, nuevo
   macro), y cualquier símbolo no numérico seguido de un solo dígito al
   final (ej. `"3891542,1"`, `"2546408_6"`, `"881511/9"`) se trata como
   separador de RUC igual que `-`/`*` (extensión de
   `derivar_cliente_id_limpio`).
2. **Clientes no identificables**: ids que son puro texto (nombres de
   persona cargados por error, ej. `"ABRAHAM"`, `"SIN NOMBRE"`) quedaban
   vacíos tras la limpieza y el legacy caía a usar el id original como
   si fuera válido -- mezclando clientes distintos que comparten el
   mismo nombre/placeholder. Decisión del usuario: excluirlos de la
   segmentación (`cliente_id_limpio` = NULL, filtrado explícito en
   `int_clientes_mapeo_limpio`/`int_clientes_limpio`), no inventarles un
   id.
3. **`_conditions()` (canibalización, notebook)**: ver Fase 4
   Canibalización arriba -- bug de `R1_acumulado` chequeado dos veces.
4. **Ventanas móviles no eran de meses cerrados**: `int_ventas_12m` y
   `fct_ventas_36m` usaban `GETDATE()` directo como límite superior,
   mezclando el mes en curso (parcial) con meses ya cerrados. El
   legacy (`view_ventas_ahorrazo_filtradas_12m`) ya lo resolvía bien
   con un CTE "limites" -- se portó ese mismo criterio vía el nuevo
   macro `fecha_corte_mes_cerrado()`.
5. **`producto_id` no es puramente numérico**: ver Top 300 arriba.

## Decisiones de arquitectura tomadas en el camino (no estaban en el plan original)

- **`int_ventas_12m`** (`models/intermediate/`): el plan original tenía
  a Top 300 y Mayoristas calculando su propia ventana de 12 meses por
  separado. Se detectó la duplicación (el legacy ya comparte
  exactamente esta ventana entre los 2 vía
  `view_ventas_ahorrazo_filtradas_12m`) y se extrajo a un solo modelo
  compartido en `intermediate/`.
- **Entorno de desarrollo local, no WSL todavía**: el plan original
  asumía dbt instalado directo en WSL (junto con Airflow). Para
  iterar rápido se armó un entorno local (Windows, Git Bash, Python
  3.12 venv) conectado por VPN al server -- `profiles.yml`/`.env` viven
  en la raíz del repo (gitignorados) en vez de `~/.dbt/`, con
  `DBT_PROFILES_DIR` apuntando ahí (`activar.sh` automatiza esto). Ver
  `README.md` ("Setup local"). Migrar esto a WSL/Airflow sigue siendo
  Fase 5, no se tocó todavía.
