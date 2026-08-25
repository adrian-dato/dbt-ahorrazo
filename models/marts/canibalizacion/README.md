# marts/canibalizacion/

Reemplaza la cadena `proc_1_36m.sql` → `proc_2_36m.sql` →
`canibalizacion_v1_usado.ipynb` de `canibalizacion_ahorrazo`. Ver
`propuesta_reingenieria_pipeline.md` en ese repo para el detalle completo
(es el proyecto más avanzado del portfolio — sirve de referencia).

`fct_ventas_36m` -- portado (Fase 1). Idéntico en lógica al original de
`canibalizacion_ahorrazo/models/marts/`, con un solo cambio: la var
`meses_ventana` pasó a llamarse `meses_ventana_canibalizacion` para no
chocar con las vars de los otros proyectos en el `dbt_project.yml`
compartido. Las reglas de exclusión (`id_empresa`, `bolsa`, `egre`/`servi`,
cliente de test) siguen inline por ahora -- se mueven a
`ref('int_ventas_elegibles')` recién en Fase 3.

Pendientes (Fase 4.1 de `PLAN_MAESTRO_REINGENIERIA.md`):
- `fct_ventas_36m_pivotado.sql` — usa el seed `dim_sucursal_mapeo`
  (ya portado a `seeds/`) en vez del
  `PIVOT ... FOR pdv_id IN ([3],[5],[6])` hardcodeado.
- `dim_cliente_tipo_migracion.sql` — traduce `_conditions()`
  (el `df.apply(axis=1)` del notebook actual) a `LAG()`/window functions.

## `fct_ventas_agrupadas_24m` — reemplazo de un script legacy sin orquestar

Reemplaza `scripts-sql-ahorrazo/prod/ventas_agrupadas_24m.sql`
(`dbo.ventas_ahorrazo_agrupadas_24m`) -- tabla fuente de un `.pbix` de
Canibalización que nunca tuvo ningún proceso que la volviera a correr.
Grano mes × cliente_id_limpio × pdv_id × categoria_1-4 × marca ×
tipo_persona, con `unidades`/`venta_gs`/`cant_tickets`.

3 decisiones tomadas a propósito distinto al legacy, confirmadas con el
usuario: ventana anclada a `periodo_max` (no `GETDATE()`), filtros de
producto vía `int_productos_limpio` (más estrictos -- también excluye
Activo/Insumos y `productos_excluidos`), y `tipo_persona` vía la macro
actual (no la heurística vieja del script). Detalle completo en el
comentario de cabecera del modelo.

**Estado: código escrito, sin correr contra la base real todavía.**
