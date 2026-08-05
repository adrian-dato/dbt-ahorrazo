-- Reemplaza ranking_metricas_2025() (top_300_productos.ipynb). Grano:
-- (ambito, producto_id). ambito = 'GLOBAL' o el pdv_id real -- mismo
-- patrón que el notebook (concatena resultado global + por sucursal,
-- cada uno normalizado dentro de su propio ámbito -- ver
-- normalizar_log_0_100, partition by ambito).
--
-- Fuente: int_ventas_elegibles (ya excluye empresa/categoría/cliente
-- test/producto excluido -- el notebook aplicaba la exclusión de
-- producto aparte, acá ya viene resuelta).

{{ config(materialized='view') }}

with ventas as (
    select *
    from {{ ref('int_ventas_elegibles') }}
    where fecha_venta >= dateadd(month, -{{ var('top300_ventana_meses') }}, getdate())
      and fecha_venta < getdate()
),

union_ambitos as (
    select 'GLOBAL' as ambito, producto_id, ticket_id, unidades, venta_gs, fecha_venta
    from ventas

    union all

    select cast(pdv_id as varchar(50)) as ambito, producto_id, ticket_id, unidades, venta_gs, fecha_venta
    from ventas
),

kpis as (
    select
        ambito,
        producto_id,
        count(distinct ticket_id)   as tickets_por_producto,
        sum(unidades)               as unidades_totales,
        sum(venta_gs)               as ventas,
        count(distinct fecha_venta) as dias_con_ventas
    from union_ambitos
    group by ambito, producto_id
),

derivadas as (
    select
        ambito,
        producto_id,
        tickets_por_producto,
        unidades_totales,
        ventas,
        dias_con_ventas,
        case when tickets_por_producto = 0 then 0.0
             else unidades_totales * 1.0 / tickets_por_producto end as unidades_por_ticket,
        case when dias_con_ventas = 0 then 0.0
             else unidades_totales * 1.0 / dias_con_ventas end as unidades_por_dia
    from kpis
),

sobre_umbral as (
    -- Filtro de umbral (top300_umbral_ventas_gs), igual que el notebook:
    -- se aplica DESPUÉS de agregar, ANTES de normalizar.
    select *
    from derivadas
    where ventas > {{ var('top300_umbral_ventas_gs') }}
)

select
    ambito,
    producto_id,
    tickets_por_producto,
    unidades_totales,
    ventas,
    dias_con_ventas,
    unidades_por_ticket,
    unidades_por_dia,
    {{ normalizar_log_0_100('ventas', 'ambito') }}                as norm_ventas,
    {{ normalizar_log_0_100('tickets_por_producto', 'ambito') }}  as norm_tickets,
    {{ normalizar_log_0_100('unidades_por_dia', 'ambito') }}      as norm_unidades_dia,
    {{ normalizar_log_0_100('unidades_por_ticket', 'ambito') }}   as norm_unidades_ticket
from sobre_umbral
