-- Para qué sirve: tabla final de clasificación mayorista v3, grano
-- cliente_id_limpio -- puntaje 0-3 y nivel_mayorista. Reemplaza
-- "resultado" del notebook (analisis_mayoristas_v3.ipynb, sección 4) --
-- el notebook deja de escribir esto a mano por pandas, esto YA es la
-- fuente. Análogo a dim_clientes_mayoristas (v2), pero con C1/C2
-- corregidos por unidad_medida -- TODAVÍA PROTOTIPO, no reemplaza a
-- dim_clientes_mayoristas como fuente de producción hasta que v3 se
-- valide y se decida el cutover (ver PENDIENTES.md).
--
-- C1/C2: "cumple si cumple en CUALQUIER unidad de medida" -- max()
-- sobre mayoristas_v3_metricas_unidad (0/1, max = OR).
--
-- C3: venta PROMEDIO POR TICKET, no la suma total del período -- la
-- suma mezclaría "compra mucho por visita" con "visita muchas veces"
-- (mismo problema conceptual que upt vs. unidades totales en C1).
-- ventas_totales se conserva como columna informativa, NO alimenta el
-- puntaje. A diferencia de C1/C2, C3 es GLOBAL: entran TODAS las
-- unidades de medida (incluidas Blis/Metros/Ramo, que no tienen C1/C2
-- propio pero sí venta) -- por eso lee directo de int_ventas_12m, no de
-- mayoristas_v3_tickets_unidad (que filtra a propósito solo
-- Unid/KILOS/LITROS/Pack).

{{ config(materialized='table') }}

with c1_c2 as (
    select
        cliente_id_limpio,
        max(c1_upt_alto)         as c1_upt_alto,
        max(c2_pct_grandes_alto) as c2_pct_grandes_alto
    from {{ ref('mayoristas_v3_metricas_unidad') }}
    group by cliente_id_limpio
),

venta_por_ticket as (
    select
        cliente_id_limpio,
        ticket_id,
        sum(venta_gs) as venta_gs
    from {{ ref('int_ventas_12m') }}
    group by cliente_id_limpio, ticket_id
),

ventas_cliente as (
    select
        cliente_id_limpio,
        avg(venta_gs * 1.0) as venta_promedio_ticket,
        sum(venta_gs)       as ventas_totales
    from venta_por_ticket
    group by cliente_id_limpio
),

umbral_c3 as (
    select distinct
        percentile_cont(0.75) within group (order by venta_promedio_ticket) over () as umbral
    from ventas_cliente
),

criterios as (
    select
        v.cliente_id_limpio,
        v.venta_promedio_ticket,
        v.ventas_totales,
        isnull(c.c1_upt_alto, 0)         as c1_upt_alto,
        isnull(c.c2_pct_grandes_alto, 0) as c2_pct_grandes_alto,
        case when v.venta_promedio_ticket >= u.umbral then 1 else 0 end as c3_ventas_alto,
        -- Expuesto tal cual (no recalculado por ningún consumidor) --
        -- mismo valor repetido en cada fila, a propósito: así cualquiera
        -- que lea esta tabla (notebook, Power BI) tiene el corte de C3 a
        -- mano sin una query aparte.
        u.umbral as umbral_c3
    from ventas_cliente v
    left join c1_c2 c
        on v.cliente_id_limpio = c.cliente_id_limpio
    cross join umbral_c3 u
)

select
    cliente_id_limpio,
    venta_promedio_ticket,
    ventas_totales,
    c1_upt_alto,
    c2_pct_grandes_alto,
    c3_ventas_alto,
    umbral_c3,
    (c1_upt_alto + c2_pct_grandes_alto + c3_ventas_alto) as puntaje,
    case (c1_upt_alto + c2_pct_grandes_alto + c3_ventas_alto)
        when 3 then 'Alto'
        when 2 then 'Medio'
        when 1 then 'Potencial'
        else 'Minorista'
    end as nivel_mayorista
from criterios
