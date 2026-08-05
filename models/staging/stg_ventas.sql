-- 1:1 sobre la fact transaccional. Vista, sin materializar: a 238M+ filas,
-- el filtro de ventana temporal se aplica en cada modelo consumidor
-- (fct_ventas_36m, int_ventas_mensual_producto_pdv, int_ventas_filtradas_12m),
-- no acá.
--
-- Excluye cliente_id NULL: confirmado con datos reales (2 filas sobre
-- 238M+, ver investigación en el equipo) que son ventas de mostrador
-- anónimas (sin cliente_id NI timbrado) -- no hay cliente al que
-- atribuirlas, y el INNER JOIN de fct_ventas_36m las descartaría de
-- todas formas. Se filtra acá, explícito, en vez de dejar que el join
-- las descarte en silencio más abajo.
select
    cliente_id,
    producto_id,
    pdv_id,
    fecha_venta,
    venta_gs,
    unidades,
    timbrado,
    factura_nro
from {{ source('dato_solutions', 'Ventas_Ahorrazo') }}
where cliente_id is not null
