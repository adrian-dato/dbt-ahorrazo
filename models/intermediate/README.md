# intermediate/

Capa de reglas de negocio **compartidas por los 3 proyectos**. Nada acá es
específico de canibalización, top 300 o mayoristas — si un modelo termina
siéndolo, no va en esta carpeta.

Pendientes de construir (Fase 2 y Fase 3 de `PLAN_MAESTRO_REINGENIERIA.md`,
no incluidos en el scaffold inicial porque requieren validación regla por
regla contra la base real antes de programarse):

- **`int_clientes_mapeo_limpio.sql`** (Fase 2 — máxima prioridad del
  portfolio). Reemplaza `scripts-sql-ahorrazo/prod/clientes_mapeo_limpio.sql`
  (`sp_refresh_clientes_mapeo_limpio`): hoy una única transacción abierta
  de ~1h+ que bloquea a los 3 proyectos. Debe portar, regla por regla, la
  limpieza de `cliente_id`/`nombre` (mayúsculas, remoción de acentos/
  espacios/`|`/letras, colapso por `-`/`*`, dedup determinístico) como
  modelo incremental.
- **`int_ventas_elegibles.sql`** (Fase 3). Reemplaza las 3 implementaciones
  hoy inconsistentes de las reglas de exclusión (`id_empresa = 3`,
  `categoria_2 NOT LIKE '%bolsa%'`, `categoria_1 NOT LIKE '%egre%'/'%servi%'`,
  cliente de test excluido) que hoy viven por separado en
  `proc_1_ventas_36m_agrupado.sql`, `ventas_filtradas_12m_usar_este_rfm_clustering.sql`
  y una lista hardcodeada en `top_300_productos.ipynb`.
