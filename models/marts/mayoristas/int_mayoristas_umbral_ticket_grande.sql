-- Reemplaza calcular_umbral_ticket_grande() (analisis_mayoristas_v2.ipynb):
-- umbral = Q3 + 1.5*IQR sobre la distribución de unidades por ticket de
-- TODO el universo de 12 meses (no por sucursal). Se calcula UNA sola
-- vez acá y se reutiliza en los 4 ámbitos (GLOBAL/SL/R1/R2, ver
-- int_mayoristas_metricas_cliente) para que el corte de "ticket grande"
-- sea comparable entre sucursales -- mismo criterio que el notebook.
--
-- PERCENTILE_CONT en SQL Server requiere OVER() (es una función de
-- ventana, no un agregado simple) -- sin PARTITION BY da el mismo valor
-- en cada fila, por eso el DISTINCT/TOP al final para quedarse con 1 fila.

{{ config(materialized='view') }}

with unidades_por_ticket as (
    -- Excluye tickets con unidades <= 0 (devoluciones), igual que el notebook.
    select
        ticket_id,
        sum(unidades) as unidades_ticket
    from {{ ref('int_ventas_12m') }}
    group by ticket_id
    having sum(unidades) > 0
),

percentiles as (
    select distinct
        percentile_cont(0.25) within group (order by unidades_ticket) over () as q1,
        percentile_cont(0.75) within group (order by unidades_ticket) over () as q3
    from unidades_por_ticket
)

select
    q1,
    q3,
    q3 + 1.5 * (q3 - q1) as umbral_ticket_grande
from percentiles
