-- Cuanto de la venta de la cadena entra al analisis de Mayoristas y
-- cuanto queda afuera, con el motivo de cada exclusion.
--
-- Es el numero que hace falta para abrir la presentacion. Sin el, la
-- primera pregunta de cualquiera que mire los resultados -- "esto es
-- sobre todo, o sobre una parte?" -- se contesta con un "creo que".
--
-- Las exclusiones no son un descarte de datos malos: son decisiones de
-- negocio sobre que es una venta relevante para clasificar clientes. Una
-- bolsa de supermercado no dice nada sobre si alguien revende, y un
-- servicio tampoco. Esta consulta las pone en numeros para poder
-- defenderlas.
--
-- SIN `declare`. Las variables de T-SQL viven solo dentro de su lote, y
-- casi todos los clientes de SQL mandan cada statement en un lote propio:
-- la consulta terminaba filtrando `between null and null` y devolviendo
-- cero filas sin avisar. La ventana entra como CTE y se resuelve dentro
-- de la misma consulta.
--
-- La ventana se toma de int_ventas_12m_tabla en vez de recalcularla, asi
-- la comparacion es contra exactamente el mismo periodo que se analizo y
-- no se duplica la regla de "12 meses cerrados".
--
-- Recorre la fact completa. Tarda. Es de una sola vez, para la
-- presentacion. SQL plano contra los esquemas de dbt.


-- 0. Que periodo se esta comparando.
select min(fecha_venta) as ventana_desde, max(fecha_venta) as ventana_hasta
from intermediate.int_ventas_12m_tabla;


-- 1. El reparto: cada linea de venta del periodo, con el motivo por el
--    que entro o no al analisis. El orden de los CASE importa -- una
--    linea puede cumplir dos motivos y se cuenta en el primero.
with ventana as (
    select min(fecha_venta) as desde, max(fecha_venta) as hasta
    from intermediate.int_ventas_12m_tabla
),

clasificado as (
    select
        case
            when p.producto_id is null                        then '1 - producto sin ficha en el catalogo'
            when p.id_empresa <> 3                            then '2 - producto de otra empresa del grupo'
            when isnull(p.categoria_2, '') like '%bolsa%'      then '3 - bolsas de supermercado'
            when isnull(p.categoria_1, '') like '%egre%'       then '4 - egresos, no es venta a cliente'
            when isnull(p.categoria_1, '') like '%servi%'      then '5 - servicios'
            when isnull(p.categoria_1, '') like '%activo%'     then '6 - activos de la empresa'
            when isnull(p.categoria_1, '') like '%insumos%'    then '7 - insumos internos'
            when pe.producto_id is not null                   then '8 - producto excluido a mano'
            when isnull(c.cliente_id_limpio, '') = '44444401' then '9 - cliente de prueba'
            else                                                   '0 - ENTRA AL ANALISIS'
        end                as motivo,
        v.venta_gs         as venta_gs,
        c.cliente_id_limpio as cliente_id_limpio
    from staging.stg_ventas v
    cross join ventana w
    left join staging.stg_clientes_mapeo c
        on v.cliente_id = c.cliente_id
    left join staging.stg_productos p
        on cast(v.producto_id as varchar(100)) = cast(p.producto_id as varchar(100))
    left join seeds.productos_excluidos pe
        on cast(v.producto_id as varchar(100)) = cast(pe.producto_id as varchar(100))
    where v.fecha_venta >= w.desde
      and v.fecha_venta <= w.hasta
)

select
    motivo,
    count(*)                                   as lineas,
    sum(cast(venta_gs as decimal(19, 4)))      as venta_gs,
    count(distinct cliente_id_limpio)          as clientes
from clasificado
group by motivo
order by motivo;


-- 2. Cuanto pesa cada unidad de medida dentro de lo que entra.
--
--    Sin count(distinct): la version anterior contaba tickets y clientes
--    distintos sobre 55 millones de filas y pasaba de media hora. Lineas
--    y venta salen de un GROUP BY normal y alcanzan para el slide.
--
--    Blis, Metros y Ramo entran en C3, que es en guaranies, pero no en C1
--    ni en C2: casi el 100% de esas facturas lleva una sola pieza y no hay
--    corte posible que separe una compra grande de una normal.
select
    p.unidad_medida,
    case
        when p.unidad_medida in ('Unid', 'KILOS', 'LITROS', 'Pack')
            then 'entra en los tres criterios'
        else 'solo entra en C3'
    end                                      as alcance,
    count(*)                                 as lineas,
    sum(cast(v.venta_gs as decimal(19, 4)))  as venta_gs
from intermediate.int_ventas_12m_tabla v
inner join intermediate.int_productos_limpio p
    on v.producto_id = p.producto_id
group by p.unidad_medida
order by venta_gs desc;


-- 2 bis. Facturas y clientes por unidad de medida, para las cuatro que
--    entran en C1 y C2. Sale de mayoristas_v3_tickets_unidad, que ya esta
--    agregada a grano factura: 8 millones de filas en vez de 55, y los
--    distintos se calculan sobre eso.
select
    unidad_medida,
    count(*)                            as facturas_por_unidad,
    count(distinct ticket_id)           as facturas_distintas,
    count(distinct cliente_id_limpio)   as clientes
from marts_mayoristas.mayoristas_v3_tickets_unidad
group by unidad_medida
order by facturas_por_unidad desc;


-- 3. Cuantos clientes quedarian sin ningun criterio de volumen medible,
--    es decir los que solo compraron en Blis, Metros o Ramo. Son clientes
--    clasificados igual -- por C3 -- pero de los que no se sabe nada sobre
--    su volumen.
select count(*) as clientes_solo_en_unidades_sin_corte
from (
    select v.cliente_id_limpio
    from intermediate.int_ventas_12m_tabla v
    inner join intermediate.int_productos_limpio p
        on v.producto_id = p.producto_id
    group by v.cliente_id_limpio
    having sum(case when p.unidad_medida in ('Unid', 'KILOS', 'LITROS', 'Pack') then 1 else 0 end) = 0
) t;
