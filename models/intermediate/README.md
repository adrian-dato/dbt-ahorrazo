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
  reemplaza a `stg_clientes_mapeo` como fuente de ningún mart.
- **`int_clientes_limpio`** — hecho, mismo estado "en paralelo" que el
  anterior.
- **`int_ventas_elegibles.sql`** (Fase 3, pendiente). Reemplaza las 3
  implementaciones hoy inconsistentes de las reglas de exclusión
  (`id_empresa = 3`, `categoria_2 NOT LIKE '%bolsa%'`, `categoria_1 NOT LIKE
  '%egre%'/'%servi%'`, cliente de test excluido) que hoy viven por separado
  en `proc_1_ventas_36m_agrupado.sql`, `ventas_filtradas_12m_usar_este_rfm_clustering.sql`
  y una lista hardcodeada en `top_300_productos.ipynb`.

## Validación pendiente — dos capas, no una

`analyses/validar_clientes_mapeo_limpio.sql` compara el modelo nuevo
contra el legacy, pero eso solo prueba *consistencia* (que ambos den lo
mismo), no *corrección* — nunca se confirmó con certeza que la
heurística legacy resuelva bien los ids sucios (hay volumen real de ids
sucios y esto nunca se validó a fondo). Por eso hace falta una segunda
capa, independiente del legacy:

- `analyses/perfilar_calidad_cliente_id.sql` — perfila los `cliente_id`
  crudos directamente (sin pasar por ninguna heurística) para detectar
  patrones que la limpieza actual (heredada 1:1 del proceso KNIME/legacy)
  no contempla — ej. caracteres además de espacio/tab/letra/`-`/`*` que
  hoy sobreviven sin tratamiento y podrían estar generando falsos
  "no-duplicados" (variantes de un mismo cliente que no colapsan al mismo
  `cliente_id_limpio`).

Ninguno de los dos se puede correr desde este entorno (sin conexión a la
base real) — quedan pendientes de correr contra la base real y reportar
resultados antes de dar por válida la limpieza, sea legacy o nueva.

## Siguiente paso para "cerrar" la Fase 2

1. Correr `analyses/perfilar_calidad_cliente_id.sql` contra la base real
   y revisar la sección "otros caracteres" — si aparece volumen, la
   limpieza (legacy y nueva, portada 1:1) se queda corta y hay que
   extender `limpiar_id`/`derivar_cliente_id_limpio` antes de confiar en
   el resultado.
2. Correr `analyses/validar_clientes_mapeo_limpio.sql` para confirmar
   consistencia con el legacy (una vez resuelto el punto 1, no antes).
3. Recién entonces: repuntar `stg_clientes_mapeo` a
   `ref('int_clientes_mapeo_limpio')` y `stg_clientes_limpio` a
   `ref('int_clientes_limpio')` en vez de sus `source()` actuales.
   `fct_ventas_36m` y todo lo que se construya en Fase 3/4 queda
   corriendo sobre el proceso nuevo recién en ese momento.
