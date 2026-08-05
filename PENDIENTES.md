# Pendientes

Una sola lista de qué falta validar/decidir, para no perder el hilo bajo
presión de tiempo. Ver `../PLAN_MAESTRO_REINGENIERIA.md` para el plan
completo por fases.

## Fase 2 — clientes_mapeo_limpio: NO CONFIRMADO TODAVÍA

- [ ] Terminar `dbt build --select int_clientes_normalizados int_clientes_mapeo_limpio int_clientes_limpio --full-refresh`
- [ ] Correr `analyses/validar_clientes_mapeo_limpio.sql`:
  - `conteo_solo_nuevo` **tiene que dar 0** (si no, hay un bug real, no una mejora).
  - `conteo_valor_distinto` / `conteo_solo_legacy` > 0 es esperado -- confirmar
    (sección 2 del archivo) que las filas que difieren encajan en los
    patrones ya identificados (símbolos en los extremos, separador raro
    + 1 dígito, clientes no identificables excluidos) y no algo nuevo.
- [ ] **Recién después de validar**: repuntar `stg_clientes_mapeo`/`stg_clientes_limpio`
  de sus `source()` actuales a `ref('int_clientes_mapeo_limpio')`/`ref('int_clientes_limpio')`.
- **No usar `int_clientes_mapeo_limpio`/`int_clientes_limpio` desde ningún mart nuevo hasta validar esto.**

## Fase 3 — reglas de exclusión compartidas (`int_ventas_elegibles`)

- [x] Modelo escrito + seed `productos_excluidos.csv` (lista real, sacada
  de `top_300_productos.ipynb`, no inventada).
- [x] Confirmado contra la base real: `dbt build --select +int_ventas_elegibles` -- 13/13 en verde.
- [ ] Limpieza opcional, no bloqueante: migrar `fct_ventas_36m` para que
  use `ref('int_ventas_elegibles')` en vez de su copia inline de las
  mismas reglas.

## Fase 4 — marts por proyecto

### Canibalización -- CONFIRMADO contra la base real (8/8, incluye accepted_values de los 16 tipo_cliente)
- [x] `fct_ventas_36m_pivotado` -- construido y testeado.
- [x] `dim_cliente_tipo_migracion` -- construido y testeado.
  **DECISIÓN QUE NECESITA CONFIRMACIÓN DE NEGOCIO ANTES DE FASE 6**:
  el legacy (`_conditions()` en el notebook) tiene un bug real -- la
  categoría "Cliente SL, R1 y R2" chequea `R1_acumulado` dos veces y
  nunca `SL_acumulado`, así que cualquier cliente con actividad en R1+R2
  (sin SL) queda mal etiquetado como "SL, R1 y R2" en vez de "Dual R1 y
  R2". Se portó la versión CORREGIDA. Efecto: al comparar contra el
  legacy, NO va a coincidir 1:1 en esas dos categorías puntuales (sí
  debería coincidir la suma de ambas). Confirmar con el equipo de
  negocio que corregir esto es lo que quieren antes de cortar a
  producción -- no asumir.

### Top 300
- [x] `int_top300_kpis` + `top300_ranking` -- escritos (lógica leída del
  notebook real: KPIs, normalización log 0-100, Puntaje Final, buckets).
- [x] Se corrigió error 4109 (OVER anidado) en `int_top300_kpis`.
- [x] Se extrajo `int_ventas_12m` (ventana móvil de 12 meses,
  COMPARTIDA con Mayoristas -- antes cada proyecto la hubiera calculado
  por separado, ahora es un solo modelo en `intermediate/`). Top 300 ya
  consume este modelo, no filtra por su cuenta.
- [ ] Sin correr todavía contra la base real (`dbt build --select
  +top300_ranking` -- vuelve a re-scanear Ventas_Ahorrazo por las
  columnas nuevas de stg_ventas, no debería ser tan largo como el
  full-refresh de Fase 2).
- [ ] Pendiente, no bloqueante: enriquecer con metadata de producto
  (nombre/categoria/precio) -- ver `models/marts/top_300/README.md`.

### Mayoristas
- [ ] Todo pendiente (`fct_features_cliente_*`). `int_ventas_12m` (ver
  arriba) ya está listo para que Mayoristas lo reutilice directamente en
  vez de duplicar el filtro de ventana -- no repetir esa parte.
