# marts/canibalizacion/

Reemplaza la cadena `proc_1_36m.sql` → `proc_2_36m.sql` →
`canibalizacion_v1_usado.ipynb` del repo `canibalizacion_ahorrazo`. El detalle
del diagnóstico está en `propuesta_reingenieria_pipeline.md`, en ese repo.

## Dos metodologías conviviendo

La **v1** clasifica a cada cliente en un tipo de migración entre sucursales.
`fct_ventas_36m` arma la ventana de 36 meses, `fct_ventas_36m_pivotado` la abre
por sucursal usando el seed `dim_sucursal_mapeo`, y `dim_cliente_tipo_migracion`
aplica las condiciones que en el notebook estaban en un `df.apply(axis=1)`.

La **v3** trabaja con eventos de migración en lugar de con un tipo fijo por
cliente. Son cuatro modelos: `int_canibalizacion_migracion_base`,
`dim_cliente_migracion_eventos`, `fct_canibalizacion_evolutivo_cliente` y
`fct_canibalizacion_migracion_resumen`, portados de `canibalizacion_v3.py`.

**El DAG semanal reconstruye solo la cadena de la v1.** Corre
`dbt build --select +dim_cliente_tipo_migracion`, y los cuatro modelos de la v3
no son ancestros de ese modelo, así que ninguna corrida programada los toca:
quedan con la ventana del día en que alguien los corrió a mano. Son dos
decisiones separadas: cambiar el selector del DAG a `+tag:canibalizacion`, que no
depende de validar nada, y el cutover de v1 a v3, que sí.

## `fct_ventas_agrupadas_24m`

Reemplaza a `scripts-sql-ahorrazo/prod/ventas_agrupadas_24m.sql`, que escribía
`dbo.ventas_ahorrazo_agrupadas_24m`. Esa tabla alimenta un `.pbix` de
Canibalización y no tenía ningún proceso que la volviera a correr. Ahora se
reconstruye desde el DAG mensual.

El grano es mes × cliente × sucursal × las cuatro categorías × marca ×
tipo de persona, con unidades, venta y cantidad de tickets.

Se apartó del script original en tres puntos, confirmados con el usuario. La
ventana se ancla al período máximo del dato y no a `GETDATE()`. Los filtros de
producto salen de `int_productos_limpio`, que además de lo que excluía el script
saca activos, insumos y la lista de `productos_excluidos`. Y `tipo_persona` sale
de la macro compartida en lugar de la heurística que traía el script. El motivo
de cada uno está en el comentario de cabecera del modelo.

## Nota sobre las variables

La ventana de este proyecto se llama `meses_ventana_canibalizacion` y no
`meses_ventana`, porque el `dbt_project.yml` es compartido con los otros dos
proyectos y los nombres cortos se pisaban entre sí.
