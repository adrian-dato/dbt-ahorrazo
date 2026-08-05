-- Reemplaza ranking_metricas_2025() (top_300_productos.ipynb). Grano:
-- (ambito, producto_id). ambito = 'GLOBAL' o el pdv_id real -- mismo
-- patrón que el notebook (concatena resultado global + por sucursal,
-- cada uno normalizado dentro de su propio ámbito).
--
-- Fuente: int_ventas_elegibles (ya excluye empresa/categoría/cliente
-- test/producto excluido).
--
-- La normalización logarítmica se separa en etapas (con_min -> con_log
-- -> con_minmax_log -> final) porque SQL Server no permite anidar una
-- función de ventana dentro del argumento de otra (error 4109) -- cada
-- MIN/MAX() OVER() de acá opera sobre una columna ya materializada en
-- el paso anterior, nunca sobre otro OVER() en vivo.

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
),

con_min as (
    -- Etapa 1: mínimo de cada métrica por ámbito, como columna plana.
    select
        *,
        min(ventas) over (partition by ambito)               as min_ventas,
        min(tickets_por_producto) over (partition by ambito) as min_tickets,
        min(unidades_por_dia) over (partition by ambito)     as min_unidades_dia,
        min(unidades_por_ticket) over (partition by ambito)  as min_unidades_ticket
    from sobre_umbral
),

con_log as (
    -- Etapa 2: log(1 + valor - mínimo), sobre columnas ya planas.
    select
        *,
        log(1 + ventas - min_ventas)                      as log_ventas,
        log(1 + tickets_por_producto - min_tickets)        as log_tickets,
        log(1 + unidades_por_dia - min_unidades_dia)       as log_unidades_dia,
        log(1 + unidades_por_ticket - min_unidades_ticket) as log_unidades_ticket
    from con_min
),

con_minmax_log as (
    -- Etapa 3: min/max de los valores logaritmizados, por ámbito.
    select
        *,
        min(log_ventas) over (partition by ambito)          as min_log_ventas,
        max(log_ventas) over (partition by ambito)          as max_log_ventas,
        min(log_tickets) over (partition by ambito)         as min_log_tickets,
        max(log_tickets) over (partition by ambito)         as max_log_tickets,
        min(log_unidades_dia) over (partition by ambito)    as min_log_unidades_dia,
        max(log_unidades_dia) over (partition by ambito)    as max_log_unidades_dia,
        min(log_unidades_ticket) over (partition by ambito) as min_log_unidades_ticket,
        max(log_unidades_ticket) over (partition by ambito) as max_log_unidades_ticket
    from con_log
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
    {{ normalizar_desde_log('log_ventas', 'min_log_ventas', 'max_log_ventas') }}
        as norm_ventas,
    {{ normalizar_desde_log('log_tickets', 'min_log_tickets', 'max_log_tickets') }}
        as norm_tickets,
    {{ normalizar_desde_log('log_unidades_dia', 'min_log_unidades_dia', 'max_log_unidades_dia') }}
        as norm_unidades_dia,
    {{ normalizar_desde_log('log_unidades_ticket', 'min_log_unidades_ticket', 'max_log_unidades_ticket') }}
        as norm_unidades_ticket
from con_minmax_log
