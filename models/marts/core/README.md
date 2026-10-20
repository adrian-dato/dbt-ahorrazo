# marts/core/

Las entidades y los hechos que comparten varios proyectos. Lo que lee más de un
análisis no pertenece a ninguno, y por eso no va en `marts/<proyecto>/`. Se
escribe en el schema `marts_core`.

Hoy tiene dos modelos: la dimensión de categorías de producto y la venta diaria
por categoría.

## `dim_categoria`

Una fila por categoría de cada uno de los cuatro niveles del catálogo, con su
clave, la clave de su padre y su ruta legible.

El nombre de una categoría no la identifica. "Dama" aparece bajo 81 categorías de
nivel 3 distintas, y 8 nombres de nivel 2, 99 de nivel 3 y 324 de nivel 4 se
repiten bajo más de un padre. Agrupar por nombre junta categorías distintas. Por
eso cada categoría se identifica por el hash de su ruta completa desde la raíz,
con el nivel como prefijo (una clave como `N3-9F2A41C07B3D`). La clave se arma en
`macros/clave_categoria.sql`, a partir del texto normalizado por
`macros/normalizar_categoria.sql`, y `int_productos_limpio` la trae en cada
producto como `categoria_key_n1` a `categoria_key_n4`. Una categoría nueva no
mueve las claves existentes, y la unicidad de `categoria_key` la prueba el
`schema.yml`.

Un nivel sin valor, que en `categoria_4` afecta a 59.028 productos con el comodín
`sin asignar.`, es un nodo `(sin asignar)` bajo su padre. Así todo producto tiene
clave en los cuatro niveles y las hojas quedan a la misma profundidad, que es lo
que pide sumar de abajo hacia arriba. `categoria_4_limpio` no sirve de
identificador: mezcla nombres de dos niveles en la misma columna.

Está en `marts_core` y no en `intermediate` porque la leen los consumidores
(Power BI, el forecasting, otros análisis) para ver los nombres de las claves;
`intermediate` es para lo que se construye y se usa adentro de dbt.

## `fct_ventas_diarias_categoria_36m`

La venta diaria por sucursal y categoría de producto, sobre una ventana de 36
meses cerrados. Una fila por día, sucursal y categoría de nivel 4, con `venta_gs`
y `lineas`.

No sale de `fct_ventas_36m`, que ya viene agregada por mes y no deja bajar a día.
Lee `int_ventas_elegibles`, que es la definición única de venta válida del
proyecto, de modo que hereda sus exclusiones y el mapeo de clientes sin repetir
ninguna regla. La clave de categoría de cada producto la toma de
`int_productos_limpio`. La ventana tiene su propia variable, `ventana_meses_36m`,
separada de la de Canibalización: cambiar una no debería mover la otra.

Cada fila trae la clave de los niveles 1, 2, 3 y 4, así que la jerarquía completa
está en la fila y subir de nivel es agrupar por otra columna. El nivel 4 equivale
a lo que `categoria_4_limpio` expresa, pero identificado por su ruta, que es lo que
lo hace único. Los nombres no se repiten en cada fila. Se leen uniendo la clave
con `dim_categoria`, y la sucursal uniendo `pdv_id` con el seed
`dim_sucursal_mapeo`:

```sql
select
    datefromparts(year(f.fecha_venta), month(f.fecha_venta), 1) as mes,
    c.ruta,
    sum(f.venta_gs) as venta_gs
from marts_core.fct_ventas_diarias_categoria_36m f
join marts_core.dim_categoria c
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

## Cómo construirlos

```
dbt build --select +fct_ventas_diarias_categoria_36m dim_categoria
```

`dim_categoria` va explícita porque la tabla diaria no la referencia y el `+` no la
alcanza. La primera corrida de la tabla diaria recorre 36 meses de la fact de
ventas: conviene hacerla fuera del horario de los DAGs y del proceso de Stock.
