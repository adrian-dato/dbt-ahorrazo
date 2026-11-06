# marts/core/

Las entidades y los hechos que comparten varios proyectos. Lo que lee más de un
análisis no pertenece a ninguno, y por eso no va en `marts/<proyecto>/`. Se
escribe en el schema `marts_core`.

Hoy tiene tres modelos: la dimensión de clientes, la dimensión de categorías de
producto y la venta diaria por categoría.

## `dim_cliente`

Una fila por cliente, con su identidad y las etiquetas que les ponen los análisis:
el nivel de Mayoristas, el segmento (Mayoristas o Minoristas) y cada cuánto compra.
Es la tabla que se une para ver quién es un cliente y en qué segmento quedó.

Incluye a todos los clientes del mapeo, no solo a los que tienen ficha en
`dbo.Clientes`. Quienes compran pero nunca se dieron de alta salen con nombre
`(sin ficha)` y `tiene_ficha` en 0; su tipo de persona se calcula igual porque solo
depende del documento. Un cliente que no compró en los últimos doce meses cerrados
no tiene fila en la clasificación de Mayoristas y sale como `Sin clasificar`.

Está al final de la cadena y no al principio. Reúne resultados de los análisis, así
que depende de ellos, y los análisis no pueden leerla: si Mayoristas leyera
`dim_cliente` y `dim_cliente` leyera a Mayoristas, dbt no podría ordenarlos y
fallaría por dependencia circular. Los análisis leen la identidad de
`int_clientes_limpio`, y cada uno toma de los demás lo que necesita desde el
resultado donde se define: la segmentación RFM, por ejemplo, toma
`segmento_mayorista` de `mayoristas_v3_resumen`.

Trae también la antigüedad: el mes de la primera compra y los meses desde entonces
hasta el cierre del último mes, igual que "Antiguedad Meses" de la segmentación
anterior. La primera compra sale de `fct_ventas_36m`, así que la antigüedad tiene
tope en 36 meses, y mientras `Ventas_pos` empiece el 17/08/2024 nadie figura con
una primera compra anterior a agosto de 2024. Un cliente sin compras en esa
ventana queda vacío.

Trae celular y mail desde el 23/10/2026, porque el tablero de segmentación usa una
sola tabla de clientes y muestra el celular. Son datos personales: el acceso a
`marts_core` tiene que estar restringido a quien los pueda ver. Las etiquetas son las
vigentes. La historia de cómo cambió
cada cliente de nivel está en el snapshot de Mayoristas,
`snapshots.mayoristas_v3_resumen_snapshot`. Cuando haya otros análisis
construidos, como el RFM, sus etiquetas se suman acá.

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
dbt build --select tag:core
```

Con la capa base y Mayoristas ya construidos, `tag:core` alcanza. La primera vez, o
cuando falta alguno de los insumos, `+fct_ventas_diarias_categoria_36m dim_categoria`
construye la venta diaria y la dimensión de categorías con todo lo que necesitan;
`dim_categoria` va explícita porque la tabla diaria no la referencia y el `+` no la
alcanza. La primera corrida de la tabla diaria recorre 36 meses de la fact de
ventas: conviene hacerla fuera del horario de los DAGs y del proceso de Stock.
