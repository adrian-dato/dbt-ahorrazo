# marts/top_300/

Reemplaza `top_300_productos.ipynb` de `top_300_productos`. Ver
`PROPUESTA_REINGENIERIA.md` en ese repo para el detalle completo
(incluye el diseño ilustrativo de estos modelos).

Pendientes (Fase 4.2 de `PLAN_MAESTRO_REINGENIERIA.md`):
- `int_ventas_mensual_producto_pdv.sql` — pre-agrega a grano
  producto×sucursal×mes, incremental por partición mensual. Reemplaza
  los 4 `groupby` que hoy corren en pandas sobre el detalle transaccional
  completo.
- `top300_ranking.sql` — suma los últimos `var('top300_ventana_meses')`
  sobre la tabla ya agregada (miles de filas, no millones), usa la macro
  `normalizar_log_0_100` (a crear en `macros/`) y los pesos/umbral
  declarados como `vars` en `dbt_project.yml`.
- Seed `productos_excluidos.csv` — reemplaza la lista hardcodeada
  `excluir_producto_id = ["442", "999994", ...]` de la celda 7 del
  notebook actual.

El orquestador Python delgado (`top300_orchestrator/`, pre-flight de
bloqueos + invocación de `dbt build` + validación + notificación) vive
en el repo `top_300_productos`, no acá — este repo es solo la capa dbt.
