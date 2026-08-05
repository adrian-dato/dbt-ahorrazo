-- Reemplaza clasificar_nivel() (analisis_mayoristas_v2.ipynb). Puntaje
-- 0-3 (1 punto por criterio) y nivel mayorista (3=Alto, 2=Medio,
-- 1=Potencial, 0=Minorista), con umbrales dinámicos Q3 calculados POR
-- ÁMBITO (a diferencia del umbral de "ticket grande", que es global --
-- ver int_mayoristas_umbral_ticket_grande).
--
-- C2 (% tickets grandes) usa el mayor entre el piso fijo
-- (mayoristas_pct_grandes_minimo) y el Q3 del ámbito -- mismo criterio
-- que PCT_GRANDES_MINIMO del notebook (ahí documentado como "30%" en un
-- comentario desactualizado, pero el valor real usado en el código es
-- 0.40 -- se porta el valor real, no el comentario).

{{ config(materialized='table') }}

with metricas as (
    select * from {{ ref('int_mayoristas_metricas_cliente') }}
),

con_percentiles as (
    select
        *,
        percentile_cont(0.75) within group (order by upt) over (partition by ambito)
            as q3_upt,
        percentile_cont(0.75) within group (order by pct_tickets_grandes) over (partition by ambito)
            as q3_pct,
        percentile_cont(0.75) within group (order by ventas_totales) over (partition by ambito)
            as q3_ventas
    from metricas
),

con_umbrales as (
    select
        *,
        q3_upt as umbral_upt,
        case when {{ var('mayoristas_pct_grandes_minimo') }} > q3_pct
             then {{ var('mayoristas_pct_grandes_minimo') }}
             else q3_pct
        end as umbral_pct,
        q3_ventas as umbral_ventas
    from con_percentiles
),

con_criterios as (
    select
        *,
        case when upt >= umbral_upt then 1 else 0 end as c1_upt_alto,
        case when pct_tickets_grandes >= umbral_pct then 1 else 0 end as c2_pct_grandes_alto,
        case when ventas_totales >= umbral_ventas then 1 else 0 end as c3_ventas_alto
    from con_umbrales
)

select
    ambito,
    cliente_id_limpio,
    tickets_unicos,
    dias_con_compra,
    upt,
    pct_tickets_grandes,
    ventas_totales,
    c1_upt_alto,
    c2_pct_grandes_alto,
    c3_ventas_alto,
    (c1_upt_alto + c2_pct_grandes_alto + c3_ventas_alto) as puntaje,
    case (c1_upt_alto + c2_pct_grandes_alto + c3_ventas_alto)
        when 3 then 'Alto'
        when 2 then 'Medio'
        when 1 then 'Potencial'
        else 'Minorista'
    end as nivel_mayorista,
    umbral_upt,
    umbral_pct,
    umbral_ventas
from con_criterios
