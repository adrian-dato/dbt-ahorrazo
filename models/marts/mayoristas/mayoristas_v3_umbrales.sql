-- Para qué sirve: tabla de referencia chica (1 fila por unidad_medida)
-- con los 3 cortes usados en la metodología v3 -- para un tile/tooltip
-- de metodología en Power BI ("un ticket de Unid se considera grande a
-- partir de 67 unidades", etc.). No calcula nada nuevo -- solo junta
-- valores que ya son constantes por unidad_medida en
-- mayoristas_v3_tickets_unidad y mayoristas_v3_metricas_unidad, para no
-- obligar a Power BI a hacer un DISTINCT sobre una tabla de millones de
-- filas solo para mostrar 4.

{{ config(materialized='table') }}

select
    t.unidad_medida,
    max(t.umbral_ticket_grande) as umbral_ticket_grande,
    max(m.umbral_upt)           as umbral_upt,
    max(m.umbral_pct)           as umbral_pct
from {{ ref('mayoristas_v3_tickets_unidad') }} t
inner join {{ ref('mayoristas_v3_metricas_unidad') }} m
    on t.unidad_medida = m.unidad_medida
group by t.unidad_medida
