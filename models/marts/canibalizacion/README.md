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

## `fct_ventas_diarias_categoria_36m`

La venta diaria por sucursal y categoría de producto, sobre la misma ventana de 36
meses cerrados que usa `fct_ventas_36m`. Una fila por día, sucursal y categoría de
nivel 4, con `venta_gs` y `lineas`.

No sale de `fct_ventas_36m`, que ya viene agregada por mes y no deja bajar a día.
Lee `int_ventas_elegibles`, que es la definición única de venta válida del
proyecto, de modo que hereda sus exclusiones y el mapeo de clientes sin repetir
ninguna regla. La clave de categoría de cada producto la toma de
`int_productos_limpio`, y `int_categorias` es la tabla donde se leen sus nombres.

El nombre de una categoría no la identifica: "Dama" aparece bajo 81 categorías de
nivel 3 distintas, y 8 nombres de nivel 2, 99 de nivel 3 y 324 de nivel 4 se
repiten bajo más de un padre. Por eso la tabla no guarda `categoria_4_limpio` sino
`categoria_key_n4`, que es esa misma categoría identificada por su ruta completa.
Cada fila trae también la clave de los niveles 1, 2 y 3, así que la jerarquía
completa está en la fila: para subir de nivel alcanza con agrupar por otra
columna. Un producto sin `categoria_4` queda en un nodo `(sin asignar)` bajo su
categoría de nivel 3.

Los nombres no se repiten en cada fila. Se leen uniendo la clave con
`int_categorias`, y la sucursal uniendo `pdv_id` con el seed `dim_sucursal_mapeo`:

```sql
select
    datefromparts(year(f.fecha_venta), month(f.fecha_venta), 1) as mes,
    c.ruta,
    sum(f.venta_gs) as venta_gs
from marts_canibalizacion.fct_ventas_diarias_categoria_36m f
join intermediate.int_categorias c
    on c.categoria_key = f.categoria_key_n2
group by datefromparts(year(f.fecha_venta), month(f.fecha_venta), 1), c.ruta
order by mes, venta_gs desc;
```

Las medidas son `venta_gs` y `lineas`, las dos sumables entre niveles. Las
unidades quedaron afuera porque una categoría mezcla kilos, litros y unidades
sueltas, y los tickets y los clientes distintos porque se contarían dos veces al
subir de nivel. Las devoluciones entran con signo negativo.

Es incremental, igual que `fct_ventas_36m`: una corrida normal reprocesa los
últimos dos meses cerrados completos y un `--full-refresh` reconstruye los 36. Un
`post_hook` borra los días que salen de la ventana. El corte se define por el
calendario y no por quitar el mes más viejo, así que una corrida manual cualquier
día del mes borra lo mismo que la programada. La categoría que usa cada producto
es la actual del catálogo: si el cliente recategorizó productos, esa venta
histórica pasa a la categoría nueva. Ningún DAG la construye todavía.

## Nota sobre las variables

La ventana de este proyecto se llama `meses_ventana_canibalizacion` y no
`meses_ventana`, porque el `dbt_project.yml` es compartido con los otros dos
proyectos y los nombres cortos se pisaban entre sí.
