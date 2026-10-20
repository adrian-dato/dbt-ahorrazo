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
--
-- producto_id casteado a varchar: confirmado con datos reales que no es
-- puramente numérico ("1685-G") y que hay valores que exceden el rango
-- de int (ej. "7506295378") -- sin este cast, un JOIN contra cualquier
-- columna int (ej. un seed con producto_id inferido como int) hace que
-- SQL Server intente convertir ESTE lado a int primero (por precedencia
-- de tipos) y explota en cualquier fila con letras o números grandes,
-- aunque esa fila nunca fuera a matchear nada. Mismo criterio que ya
-- usa el legacy (CAST(producto_id AS varchar(100)) en varios scripts).
--
-- fecha_venta se pasa a date. Ventas_pos la trae como datetime2(6), con hora,
-- y la tabla anterior la traía como date. Todo lo que está de acá para abajo
-- trata esta columna como un día: las visitas de un cliente son los días
-- distintos con compra, los días con venta de un producto son los días
-- distintos en que se vendió, la venta diaria agrupa por ella y el tablero la
-- une con el calendario. Con hora incluida, cada venta contaría como un día
-- distinto sin que nada fallara. El contrato de abajo detectó la diferencia
-- el 20/10/2026, al primer build contra la tabla nueva.
--
-- El date es el de la fecha que trae el dato, tal cual. Si Ventas_pos guarda la
-- hora en UTC y no en hora de Paraguay, una venta de la noche cae en el día
-- siguiente; la consulta 6 de analyses/verificar_cambio_a_ventas_pos.sql
-- muestra a qué horas vende cada sucursal para comprobarlo.
--
-- medio_pago: ya estaba declarada en _staging__sources.yml pero nunca se
-- había seleccionado -- pedido explícito del equipo para exponerla en el
-- análisis. Es un atributo de línea/venta (igual que venta_gs o
-- unidades), no se resuelve ni se agrega acá.
--
-- Solo las ventas de Ahorrazo, id_empresa = 3. Ventas_pos trae también las de
-- Kingo, el otro supermercado del grupo (puntos de venta 1 y 2), con las que no
-- se trabaja. Ventas_Ahorrazo, la tabla anterior, venía solo con Ahorrazo
-- (puntos de venta 3, 5 y 6). Es el mismo criterio con el que int_productos_limpio
-- se queda con los productos de la empresa 3. Se filtra por la empresa y no por
-- la lista de puntos de venta, que es lo que cambia cuando se abre una sucursal.
select
    cliente_id,
    cast(producto_id as varchar(100)) as producto_id,
    pdv_id,
    cast(fecha_venta as date) as fecha_venta,
    venta_gs,
    unidades,
    timbrado,
    factura_nro,
    medio_pago
from {{ source('dato_solutions', 'Ventas_pos') }}
where cliente_id is not null
    and id_empresa = 3
