-- Reemplaza calcular_metricas() (analisis_mayoristas_v2.ipynb). Grano:
-- (ambito, cliente_id_limpio). ambito = 'GLOBAL' o sucursal_codigo
-- (SL/R1/R2, vía seed dim_sucursal_mapeo) -- mismo patrón que
-- int_top300_kpis: cada ámbito se evalúa por separado.
--
-- Las exclusiones que el notebook aplicaba (EXCLUIR_CLIENTES=["44444401-7"],
-- EXCLUIR_PRODUCTOS, los mismos 13 que Top 300) YA están cubiertas por
-- int_ventas_12m -- no se duplican acá (44444401-7 colapsa a 44444401
-- vía la limpieza de cliente_id, ya excluido en int_ventas_elegibles).

{{ config(materialized='view') }}

with ventas as (
    select * from {{ ref('int_ventas_12m') }}
    where cliente_id_limpio is not null
),

sucursales as (
    select * from {{ ref('dim_sucursal_mapeo') }}
),

union_ambitos as (
    select 'GLOBAL' as ambito, cliente_id_limpio, ticket_id, unidades, venta_gs, fecha_venta
    from ventas

    union all

    select s.sucursal_codigo as ambito, v.cliente_id_limpio, v.ticket_id, v.unidades, v.venta_gs, v.fecha_venta
    from ventas v
    inner join sucursales s on v.pdv_id = s.pdv_id
),

upt_por_ticket as (
    -- Paso 1: unidades del cliente dentro de cada ticket (no del ticket
    -- completo -- solo lo que compró ese cliente). Excluye tickets con
    -- unidades <= 0 (devoluciones).
    select
        ambito,
        cliente_id_limpio,
        ticket_id,
        sum(unidades) as upt_ticket
    from union_ambitos
    group by ambito, cliente_id_limpio, ticket_id
    having sum(unidades) > 0
),

umbral as (
    select umbral_ticket_grande from {{ ref('int_mayoristas_umbral_ticket_grande') }}
),

metricas_ticket as (
    select
        t.ambito,
        t.cliente_id_limpio,
        count(*)                                                                as tickets_unicos,
        sum(t.upt_ticket)                                                        as upt_suma,
        sum(case when t.upt_ticket > u.umbral_ticket_grande then 1 else 0 end)   as tickets_grandes
    from upt_por_ticket t
    cross join umbral u
    group by t.ambito, t.cliente_id_limpio
),

otras as (
    select
        ambito,
        cliente_id_limpio,
        count(distinct fecha_venta) as dias_con_compra,
        sum(venta_gs)               as ventas_totales
    from union_ambitos
    group by ambito, cliente_id_limpio
)

select
    m.ambito,
    m.cliente_id_limpio,
    m.tickets_unicos,
    o.dias_con_compra,
    case when m.tickets_unicos = 0 then 0.0
         else m.upt_suma * 1.0 / m.tickets_unicos end as upt,
    case when m.tickets_unicos = 0 then 0.0
         else m.tickets_grandes * 1.0 / m.tickets_unicos end as pct_tickets_grandes,
    o.ventas_totales
from metricas_ticket m
inner join otras o
    on m.ambito = o.ambito and m.cliente_id_limpio = o.cliente_id_limpio
