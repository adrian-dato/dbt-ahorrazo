-- Para qué sirve: tabla de referencia chica (1 fila por unidad_medida)
-- con los 3 cortes usados en la metodología v3 -- para un tile/tooltip
-- de metodología en Power BI ("un ticket de Unid se considera grande a
-- partir de 67 unidades", etc.). No calcula nada nuevo -- solo junta
-- valores que ya son constantes por unidad_medida en
-- mayoristas_v3_tickets_unidad y mayoristas_v3_metricas_unidad, para no
-- obligar a Power BI a hacer un DISTINCT sobre una tabla de millones de
-- filas solo para mostrar 4.
--
-- El join entre mayoristas_v3_tickets_unidad (grano ticket, millones de
-- filas) y mayoristas_v3_metricas_unidad (grano cliente, hasta ~1.6M
-- filas) NO puede hacerse directo por unidad_medida -- esa columna
-- tiene solo 4 valores, así que unir las dos tablas grandes por ahí
-- arma el producto cartesiano completo de cada lado (millones x
-- cientos de miles de filas) antes de que el GROUP BY lo colapse de
-- vuelta a 1 fila -- esto tumbó la base en la primera corrida real. En
-- cambio, cada tabla ya tiene un solo valor por unidad_medida, así que
-- primero se saca ese DISTINCT (barato, ya viene reducido) de cada
-- tabla por separado, y recién ahí se unen los dos resultados de 4
-- filas -- mismo resultado, sin el cartesiano de por medio.

{{ config(materialized='table') }}

with umbral_ticket as (
    select distinct unidad_medida, umbral_ticket_grande
    from {{ ref('mayoristas_v3_tickets_unidad') }}
),

umbral_cliente as (
    select distinct unidad_medida, umbral_upt, umbral_pct
    from {{ ref('mayoristas_v3_metricas_unidad') }}
)

select
    t.unidad_medida,
    t.umbral_ticket_grande,
    m.umbral_upt,
    m.umbral_pct
from umbral_ticket t
inner join umbral_cliente m
    on t.unidad_medida = m.unidad_medida
