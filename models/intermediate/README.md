# intermediate/

Capa de reglas de negocio **compartidas por los 3 proyectos**. Nada acá es
específico de canibalización, top 300 o mayoristas — si un modelo termina
siéndolo, no va en esta carpeta.

## Estado

- **`int_clientes_normalizados`** — hecho. Limpieza de `dbo.Clientes`
  (equivalente KNIME), calculada una sola vez.
- **`int_clientes_mapeo_limpio`** — hecho (Fase 2, máxima prioridad del
  portfolio). Reemplaza `scripts-sql-ahorrazo/prod/clientes_mapeo_limpio.sql`
  (`sp_refresh_clientes_mapeo_limpio`): hoy una única transacción abierta
  de ~1h+ que bloquea a los 3 proyectos. Incremental, portó regla por
  regla la limpieza de `cliente_id` (colapso por `-`/`*`, dedup
  determinístico). **Corre en paralelo al proceso legacy** — todavía no
  reemplaza a `stg_clientes_mapeo` como fuente de ningún mart. Validar con
  `analyses/validar_clientes_mapeo_limpio.sql` antes de ese switch.
- **`int_clientes_limpio`** — hecho, mismo estado "en paralelo" que el
  anterior.
- **`int_ventas_elegibles.sql`** (Fase 3, pendiente). Reemplaza las 3
  implementaciones hoy inconsistentes de las reglas de exclusión
  (`id_empresa = 3`, `categoria_2 NOT LIKE '%bolsa%'`, `categoria_1 NOT LIKE
  '%egre%'/'%servi%'`, cliente de test excluido) que hoy viven por separado
  en `proc_1_ventas_36m_agrupado.sql`, `ventas_filtradas_12m_usar_este_rfm_clustering.sql`
  y una lista hardcodeada en `top_300_productos.ipynb`.

## Siguiente paso para "cerrar" la Fase 2

Una vez validado (`analyses/validar_clientes_mapeo_limpio.sql` sin
diferencias, corrido contra la base real durante N días/corridas):
repuntar `stg_clientes_mapeo` a `ref('int_clientes_mapeo_limpio')` y
`stg_clientes_limpio` a `ref('int_clientes_limpio')` en vez de sus
`source()` actuales. Recién ahí `fct_ventas_36m` y todo lo que se
construya en Fase 3/4 queda corriendo sobre el proceso nuevo de punta a
punta.
