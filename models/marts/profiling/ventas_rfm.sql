-- Fuente de rfm.py (repo customer-profiling): la venta de los últimos 12 meses
-- cerrados, a grano de línea, con el segmento de Mayoristas de cada cliente.
-- rfm.py calcula el RFM por separado para cada valor de group_by_col, y acá
-- ese valor es segmento_mayorista: Mayoristas (nivel Alto) y Minoristas (los
-- otros tres niveles). Los clientes que la clasificación de Mayoristas no
-- alcanzó quedan como 'Sin clasificar' y forman su propio grupo.
--
-- Vista sobre dos tablas: int_ventas_12m_tabla ya tiene la ventana congelada y
-- las exclusiones (cliente de prueba, Kingo, productos fuera del catálogo de
-- Ahorrazo), y dim_cliente tiene la etiqueta. rfm.py vuelve a acotar por fecha
-- con su window_days, que con 365 cubre la misma ventana.
--
-- El segmento es el de la última clasificación mensual: corre después del DAG
-- mensual, cuando Mayoristas y la capa core ya se reconstruyeron.

select
    v.cliente_id_limpio,
    v.producto_id,
    v.pdv_id,
    v.fecha_venta,
    v.venta_gs,
    v.ticket_id,
    coalesce(c.segmento_mayorista, 'Sin clasificar') as segmento_mayorista
from {{ ref('int_ventas_12m_tabla') }} v
left join {{ ref('dim_cliente') }} c
    on c.cliente_id_limpio = v.cliente_id_limpio
