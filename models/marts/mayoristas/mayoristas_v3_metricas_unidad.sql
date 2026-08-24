-- Para qué sirve: C1 (UPT alto) y C2 (% tickets grandes), por
-- (cliente_id_limpio, unidad_medida) -- reemplaza metricas_por_unidad +
-- umbrales_cliente del notebook (analisis_mayoristas_v3.ipynb, sección
-- 4). Consumido por mayoristas_v3_resumen (combina "cumple en cualquier
-- unidad") y mayoristas_v3_umbrales (referencia de metodología).
--
-- Ojo, hay 2 umbrales "Q3+IQR" distintos en esta metodología, no
-- confundirlos:
--   - umbral_ticket_grande (en mayoristas_v3_tickets_unidad): Q3+3xIQR
--     sobre TICKETS individuales -- define qué es una factura grande.
--   - umbral_upt/umbral_pct (acá): percentil 75 simple sobre el
--     comportamiento YA AGREGADO de cada CLIENTE (upt promedio,
--     pct_tickets_grandes) comparado contra otros clientes -- define
--     qué tan alto tiene que ser ESE cliente respecto al resto.
--
-- C2 tiene un piso mínimo (var mayoristas_pct_grandes_minimo, mismo
-- valor 0.40 que ya usa dim_clientes_mayoristas en v2) -- nunca baja de
-- ese piso aunque el percentil 75 real del universo dé menos.
--
-- PERCENTILE_CONT en SQL Server es función de ventana (necesita OVER()),
-- no un agregado simple -- con PARTITION BY unidad_medida da el mismo
-- valor repetido en cada fila de esa unidad, por eso el DISTINCT.

{{ config(materialized='table') }}

with metricas as (
    select
        cliente_id_limpio,
        unidad_medida,
        count(*)                          as tickets_unicos,
        avg(unidades * 1.0)               as upt,
        avg(cast(ticket_grande as float))  as pct_tickets_grandes
    from {{ ref('mayoristas_v3_tickets_unidad') }}
    group by cliente_id_limpio, unidad_medida
),

percentiles as (
    select distinct
        unidad_medida,
        percentile_cont(0.75) within group (order by upt) over (partition by unidad_medida) as q3_upt,
        percentile_cont(0.75) within group (order by pct_tickets_grandes) over (partition by unidad_medida) as q3_pct
    from metricas
),

umbrales as (
    select
        unidad_medida,
        q3_upt as umbral_upt,
        case
            when q3_pct > {{ var('mayoristas_pct_grandes_minimo') }} then q3_pct
            else {{ var('mayoristas_pct_grandes_minimo') }}
        end as umbral_pct
    from percentiles
)

select
    m.cliente_id_limpio,
    m.unidad_medida,
    m.tickets_unicos,
    m.upt,
    m.pct_tickets_grandes,
    u.umbral_upt,
    u.umbral_pct,
    case when m.upt >= u.umbral_upt then 1 else 0 end as c1_upt_alto,
    case when m.pct_tickets_grandes >= u.umbral_pct then 1 else 0 end as c2_pct_grandes_alto
from metricas m
inner join umbrales u
    on m.unidad_medida = u.unidad_medida
