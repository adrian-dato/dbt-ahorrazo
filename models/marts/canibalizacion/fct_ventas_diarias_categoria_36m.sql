-- La venta diaria por sucursal y categoría de producto, sobre la ventana de
-- 36 meses cerrados de Canibalización. Una fila por día x sucursal x
-- categoría de nivel 4.
--
-- EN QUÉ SE APOYA
--   - int_ventas_elegibles: la venta válida del proyecto (empresa 3, sin
--     bolsas/egresos/servicios/activos/insumos, sin los productos de
--     productos_excluidos, sin el cliente de prueba, con el cliente ya
--     mapeado a cliente_id_limpio). Es la única definición de qué es una
--     venta para analizar; esta tabla no repite ninguna regla.
--   - int_productos_limpio: la clave de categoría de cada producto.
--     int_categorias es la tabla donde se leen el nombre y la ruta de cada
--     clave.
--   No sale de fct_ventas_36m, que ya viene agregada por mes y no permite
--   bajar a día. La ventana sí es la misma: meses_ventana_canibalizacion
--   (36) meses cerrados, calculada con fecha_corte_mes_cerrado().
--
-- EL NIVEL 4 Y LOS DEMÁS. El nivel más fino es categoria_key_n4, que
-- equivale a lo que categoria_4_limpio expresa pero identificado por la
-- ruta completa, y por eso es único. categoria_4_limpio solo guarda el
-- nombre, y un nombre como 'Dama' se repite bajo decenas de categorías de
-- nivel 3. Las claves de los niveles 1, 2 y 3 vienen en cada fila, así que
-- subir de nivel es agrupar por otra columna, sin unir contra nada: la
-- jerarquía queda implícita en la fila. Un producto sin categoria_4 queda
-- en el nodo '(sin asignar)' de su categoría de nivel 3.
--
-- Los nombres no se repiten en cada fila (serían millones de textos
-- repetidos). Se leen uniendo la clave con int_categorias.categoria_key; la
-- sucursal se lee uniendo pdv_id con el seed dim_sucursal_mapeo.
--
-- SOLO MEDIDAS QUE SE SUMAN. venta_gs y lineas se pueden sumar de un nivel
-- a otro sin error. Las unidades no: una categoría mezcla kilos, litros y
-- unidades sueltas, y sumarlos no da nada con sentido. Los tickets y los
-- clientes distintos tampoco, porque un ticket con productos de dos
-- categorías se contaría dos veces al subir de nivel. Las ventas devueltas
-- entran con su signo negativo: es venta neta.
--
-- venta_gs se suma casteada a decimal: es float en el contrato de
-- stg_ventas, y sumar floats en paralelo no da el mismo resultado entre
-- corridas porque el orden en que el motor combina los parciales cambia
-- los últimos dígitos.
--
-- INCREMENTAL por meses cerrados completos. Una corrida normal reprocesa
-- los últimos meses_lookback_incremental meses cerrados, desde el día 1, y
-- un --full-refresh reconstruye los 36. La ventana se mantiene con el
-- post_hook, que borra todo día anterior al primer día del mes en curso
-- menos 36 meses. Se define por el calendario y no por "quitar el mes más
-- viejo", así que es idempotente: una corrida manual cualquier día del mes
-- borra lo mismo que la programada. Mismo mecanismo que fct_ventas_36m.
--
-- La categoría de cada producto es la actual del catálogo. Si el cliente
-- recategorizó productos, esa venta histórica pasa a la categoría nueva.
-- Un día sin ventas de una categoría no genera fila.
--
-- La primera corrida recorre 36 meses de la fact de 238M+ filas: conviene
-- hacerla fuera del horario de los DAGs y del proceso de Stock.

{{
    config(
        materialized='incremental',
        unique_key=['fecha_venta', 'pdv_id', 'categoria_key_n4'],
        incremental_strategy='delete+insert',
        post_hook="delete from {{ this }} where fecha_venta < dateadd(month, -{{ var('meses_ventana_canibalizacion') }}, {{ fecha_corte_mes_cerrado() }})"
    )
}}

select
    v.fecha_venta,
    v.pdv_id,
    p.categoria_key_n1,
    p.categoria_key_n2,
    p.categoria_key_n3,
    p.categoria_key_n4,
    sum(cast(v.venta_gs as decimal(19, 2))) as venta_gs,
    count(*)                                as lineas
from {{ ref('int_ventas_elegibles') }} v
inner join {{ ref('int_productos_limpio') }} p
    on cast(v.producto_id as varchar(100)) = cast(p.producto_id as varchar(100))
where v.fecha_venta >= dateadd(month, -{{ var('meses_ventana_canibalizacion') }}, {{ fecha_corte_mes_cerrado() }})
  and v.fecha_venta <  {{ fecha_corte_mes_cerrado() }}
  {% if is_incremental() %}
  and v.fecha_venta >= dateadd(month, -{{ var('meses_lookback_incremental') }}, {{ fecha_corte_mes_cerrado() }})
  {% endif %}
group by
    v.fecha_venta,
    v.pdv_id,
    p.categoria_key_n1,
    p.categoria_key_n2,
    p.categoria_key_n3,
    p.categoria_key_n4
