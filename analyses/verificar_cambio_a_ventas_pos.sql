-- Comprueba que Ventas_pos puede reemplazar a Ventas_Ahorrazo como fuente de
-- ventas. El cliente informó que tienen la misma estructura y granularidad;
-- acá se verifica en vez de darlo por cierto.
--
-- Qué decide cada consulta:
--   1. Estructura. Una columna con otro tipo hace fallar el contrato de
--      stg_ventas; una columna que falta o sobra, no. Mirar la columna
--      "estado".
--   2. Cobertura. Si Ventas_pos arranca más tarde que Ventas_Ahorrazo, no
--      tiene el historial y no alcanza como fuente única: las ventanas de
--      12, 24 y 36 meses quedarían cortas. En ese caso stg_ventas tiene que
--      unir las dos tablas con una fecha de corte.
--   3. Mes a mes. En los meses que están en las dos, las filas, la venta y las
--      unidades tienen que coincidir. Una diferencia en un mes ya cerrado
--      significa que la tabla nueva no es la misma data, y los modelos
--      incrementales (int_clientes_mapeo_limpio y fct_ventas_36m) hay que
--      reconstruirlos con --full-refresh para no arrastrar la data anterior.
--   4. Granularidad. Que las líneas por factura, y la cantidad de clientes,
--      productos y sucursales de un mismo mes cerrado, sean parecidas.
--   5. Formato de los códigos. Que pdv_id y medio_pago tengan los mismos
--      valores, y que ticket_id (timbrado y factura_nro) tenga el mismo
--      formato: si cambia, una factura que está en las dos tablas se contaría
--      dos veces.
--   6. Hora de las ventas. Ventas_pos trae fecha_venta con hora (datetime2) y la
--      tabla anterior solo con fecha. stg_ventas la pasa a date, lo cual es
--      correcto solo si la hora es la de Paraguay: si fuera UTC, una venta de
--      la noche caería en el día siguiente y se movería de mes en el cierre.
--
-- SQL plano contra dbo: se pega y se corre. Recorre las dos tablas enteras,
-- así que conviene correrlo fuera del horario de los DAGs y de Stock.
-- Cuando Ventas_Ahorrazo se dé de baja este archivo deja de servir, y se
-- elimina.


-- 1. Estructura, columna por columna.
with anterior as (
    select column_name, data_type, character_maximum_length as largo
    from INFORMATION_SCHEMA.COLUMNS
    where table_schema = 'dbo' and table_name = 'Ventas_Ahorrazo'
),
nueva as (
    select column_name, data_type, character_maximum_length as largo
    from INFORMATION_SCHEMA.COLUMNS
    where table_schema = 'dbo' and table_name = 'Ventas_pos'
)
select
    coalesce(a.column_name, n.column_name) as columna,
    a.data_type as tipo_anterior, a.largo as largo_anterior,
    n.data_type as tipo_nuevo,    n.largo as largo_nuevo,
    case
        when a.column_name is null then 'solo en la nueva'
        when n.column_name is null then 'solo en la anterior'
        when a.data_type <> n.data_type or isnull(a.largo, -1) <> isnull(n.largo, -1) then 'tipo distinto'
        else 'igual'
    end as estado
from anterior a
full join nueva n on a.column_name = n.column_name
order by case when a.data_type = n.data_type and isnull(a.largo, -1) = isnull(n.largo, -1) then 1 else 0 end,
         columna;


-- 2. Cobertura de cada tabla.
select 'Ventas_Ahorrazo' as tabla, min(fecha_venta) as desde, max(fecha_venta) as hasta, count_big(*) as filas
from dbo.Ventas_Ahorrazo
union all
select 'Ventas_pos', min(fecha_venta), max(fecha_venta), count_big(*)
from dbo.Ventas_pos;


-- 3. Mes a mes: filas, venta y unidades de cada tabla. Las diferencias de los
--    meses que están en las dos tienen que dar cero.
with anterior as (
    select year(fecha_venta) * 100 + month(fecha_venta) as periodo,
           count_big(*) as filas,
           sum(cast(venta_gs as decimal(19, 2))) as venta,
           sum(cast(unidades as decimal(19, 4))) as unidades
    from dbo.Ventas_Ahorrazo
    group by year(fecha_venta) * 100 + month(fecha_venta)
),
nueva as (
    select year(fecha_venta) * 100 + month(fecha_venta) as periodo,
           count_big(*) as filas,
           sum(cast(venta_gs as decimal(19, 2))) as venta,
           sum(cast(unidades as decimal(19, 4))) as unidades
    from dbo.Ventas_pos
    group by year(fecha_venta) * 100 + month(fecha_venta)
)
select
    coalesce(a.periodo, n.periodo) as periodo,
    a.filas as filas_anterior, n.filas as filas_nueva, n.filas - a.filas as dif_filas,
    a.venta as venta_anterior, n.venta as venta_nueva, n.venta - a.venta as dif_venta,
    a.unidades as unidades_anterior, n.unidades as unidades_nueva, n.unidades - a.unidades as dif_unidades
from anterior a
full join nueva n on a.periodo = n.periodo
order by periodo;


-- 4. Granularidad en un mes cerrado que esté en las dos tablas. Cambiar las
--    fechas por el mes que muestre la consulta 3 con filas en ambas.
declare @desde date = '2026-07-01', @hasta date = '2026-08-01';

select 'Ventas_Ahorrazo' as tabla,
       count_big(*) as lineas,
       count(distinct concat(timbrado, '_', factura_nro)) as facturas,
       count_big(*) * 1.0 / nullif(count(distinct concat(timbrado, '_', factura_nro)), 0) as lineas_por_factura,
       count(distinct cliente_id) as clientes,
       count(distinct producto_id) as productos,
       count(distinct pdv_id) as sucursales
from dbo.Ventas_Ahorrazo
where fecha_venta >= @desde and fecha_venta < @hasta
union all
select 'Ventas_pos',
       count_big(*),
       count(distinct concat(timbrado, '_', factura_nro)),
       count_big(*) * 1.0 / nullif(count(distinct concat(timbrado, '_', factura_nro)), 0),
       count(distinct cliente_id),
       count(distinct producto_id),
       count(distinct pdv_id)
from dbo.Ventas_pos
where fecha_venta >= @desde and fecha_venta < @hasta;


-- 5. Formato de los códigos. Los valores de pdv_id y de medio_pago de cada
--    tabla, y un ejemplo de ticket_id.
select 'pdv_id' as campo, cast(pdv_id as varchar(50)) as valor, 'Ventas_Ahorrazo' as tabla, count_big(*) as filas
from dbo.Ventas_Ahorrazo group by pdv_id
union all
select 'pdv_id', cast(pdv_id as varchar(50)), 'Ventas_pos', count_big(*)
from dbo.Ventas_pos group by pdv_id
union all
select 'medio_pago', cast(medio_pago as varchar(255)), 'Ventas_Ahorrazo', count_big(*)
from dbo.Ventas_Ahorrazo group by medio_pago
union all
select 'medio_pago', cast(medio_pago as varchar(255)), 'Ventas_pos', count_big(*)
from dbo.Ventas_pos group by medio_pago
order by campo, valor, tabla;

select * from (
    select top 5 'Ventas_Ahorrazo' as tabla, concat(timbrado, '_', factura_nro) as ticket_id, fecha_venta
    from dbo.Ventas_Ahorrazo order by fecha_venta desc
) as anterior
union all
select * from (
    select top 5 'Ventas_pos' as tabla, concat(timbrado, '_', factura_nro) as ticket_id, fecha_venta
    from dbo.Ventas_pos order by fecha_venta desc
) as nueva;


-- 6. A qué horas se vende, en un mes cerrado. Una tienda abierta de día vende
--    entre la mañana y la noche; si las ventas aparecen concentradas de madrugada
--    o con un corrimiento de tres horas contra el horario de la tienda, la hora
--    está en UTC. Mirar también si hay ventas con hora 00:00:00 exacta: serían
--    las que no traen hora.
declare @desde_h date = '2026-07-01', @hasta_h date = '2026-08-01';

select
    datepart(hour, fecha_venta) as hora,
    count_big(*) as lineas,
    sum(case when cast(fecha_venta as time) = '00:00:00' then 1 else 0 end) as lineas_sin_hora
from dbo.Ventas_pos
where fecha_venta >= @desde_h and fecha_venta < @hasta_h
group by datepart(hour, fecha_venta)
order by hora;
