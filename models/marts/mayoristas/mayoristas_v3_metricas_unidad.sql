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
-- Q3 de upt/pct_tickets_grandes se calcula en ramas separadas por
-- unidad_medida (UNION ALL), no con PERCENTILE_CONT(...) OVER
-- (PARTITION BY unidad_medida) -- mismo motivo que en
-- mayoristas_v3_tickets_unidad: particionar la ventana por una columna
-- tan despareja (Unid+KILOS >99% de las filas) fuerza al motor a
-- repartir mal el trabajo paralelo. Acá el volumen es mucho menor (una
-- fila por cliente x unidad_medida, no por ticket), así que no llegó a
-- colgar la base, pero el mismo fix aplica por consistencia y evita que
-- vuelva a pasar si la base de clientes crece.
--
-- El OVER() vacío es obligatorio -- a diferencia de Postgres/Oracle,
-- PERCENTILE_CONT en T-SQL solo existe como función de ventana, nunca
-- como agregado simple con GROUP BY (falla con el error 10753 sin
-- OVER). No es un PARTITION BY: cada rama ya viene filtrada a una sola
-- unidad_medida. El DISTINCT colapsa las filas repetidas.

{{ config(materialized='table') }}

{% set unidades_relevantes = ['Unid', 'KILOS', 'LITROS', 'Pack'] %}

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
    {% for u in unidades_relevantes %}
    select distinct
        '{{ u }}' as unidad_medida,
        percentile_cont(0.75) within group (order by upt) over () as q3_upt,
        percentile_cont(0.75) within group (order by pct_tickets_grandes) over () as q3_pct
    from metricas
    where unidad_medida = '{{ u }}'
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
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
