# marts/canibalizacion/

Reemplaza la cadena `proc_1_36m.sql` → `proc_2_36m.sql` →
`canibalizacion_v1_usado.ipynb` de `canibalizacion_ahorrazo`. Ver
`propuesta_reingenieria_pipeline.md` en ese repo para el detalle completo
(es el proyecto más avanzado del portfolio — sirve de referencia).

`fct_ventas_36m` ya está construido y testeado en `canibalizacion_ahorrazo/models/marts/`;
se porta a este repo en Fase 1 (fundación), junto con `stg_ventas`,
`stg_productos` y `stg_clientes_mapeo`.

Pendientes (Fase 4.1 de `PLAN_MAESTRO_REINGENIERIA.md`):
- `fct_ventas_36m_pivotado.sql` — usa el seed `dim_sucursal_mapeo`
  (ya existe en `canibalizacion_ahorrazo/seeds/`) en vez del
  `PIVOT ... FOR pdv_id IN ([3],[5],[6])` hardcodeado.
- `dim_cliente_tipo_migracion.sql` — traduce `_conditions()`
  (el `df.apply(axis=1)` del notebook actual) a `LAG()`/window functions.
