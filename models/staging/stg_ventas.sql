-- 1:1 sobre la fact transaccional. Vista, sin materializar: a 238M+ filas,
-- el filtro de ventana temporal se aplica en cada modelo consumidor
-- (fct_ventas_36m, int_ventas_mensual_producto_pdv, int_ventas_filtradas_12m),
-- no acá.
select
    cliente_id,
    producto_id,
    pdv_id,
    fecha_venta,
    venta_gs
from {{ source('dato_solutions', 'Ventas_Ahorrazo') }}
