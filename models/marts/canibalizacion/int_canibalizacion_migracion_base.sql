-- Reemplaza los pasos 2-6 de canibalizacion_v3.py: ventana móvil de
-- canibalizacion_v3_ventana_meses (24) meses ANCLADA AL MÁXIMO PERÍODO
-- PRESENTE EN LOS DATOS -- no a GETDATE(), mismo criterio que el script
-- (`periodo_max = df_raw['periodo'].max()`) --, exclusión de OCASIONALES
-- (clientes con un solo mes de compra en la ventana), y clasificación
-- NUEVO/RECURRENTE por fila (primer mes del cliente en la ventana =
-- Nuevo, resto = Recurrente).
--
-- Fuente: ref('fct_ventas_36m_pivotado') en vez de la tabla legacy
-- dbo.Ventas_36_Ult_Meses_Pivotado que lee el script -- ya viene con la
-- ventana de 36 meses, las reglas de exclusión unificadas (vía
-- int_ventas_elegibles) y meses cerrados. Este modelo acota además a
-- canibalizacion_v3_ventana_meses (24) de esos 36.

{{ config(materialized='view') }}

with pivotado as (
    select
        cliente_id_limpio,
        nombre,
        anio,
        mes,
        (anio * 100 + mes) as periodo,
        SL,
        R1,
        R2
    from {{ ref('fct_ventas_36m_pivotado') }}
    -- Solo filas con al menos una compra (mismo filtro que el script,
    -- aunque en la práctica fct_ventas_36m_pivotado ya no debería traer
    -- filas 0/0/0).
    where SL > 0 or R1 > 0 or R2 > 0
),

periodo_max as (
    select max(periodo) as periodo_max from pivotado
),

en_ventana as (
    -- Equivalente a restar_meses(periodo_max, VENTANA_MESES - 1): el
    -- mes 0 del análisis es periodo_max - (ventana - 1) meses.
    select p.*
    from pivotado p
    cross join periodo_max pm
    where {{ meses_entre_periodos('pm.periodo_max', 'p.periodo') }}
          <= {{ var('canibalizacion_v3_ventana_meses') - 1 }}
),

con_meses_activos as (
    -- count(*) y no count(distinct periodo): SQL Server no permite
    -- DISTINCT dentro de una función de ventana (a diferencia de
    -- Postgres). No hace falta igual -- pivotado ya es 1 fila por
    -- (cliente_id_limpio, anio, mes), no hay períodos repetidos por
    -- cliente en esta tabla.
    select
        *,
        count(*) over (partition by cliente_id_limpio) as meses_con_compra
    from en_ventana
),

sin_ocasionales as (
    select *
    from con_meses_activos
    where meses_con_compra > 1
)

select
    cliente_id_limpio,
    nombre,
    anio,
    mes,
    periodo,
    SL,
    R1,
    R2,
    min(periodo) over (partition by cliente_id_limpio) as primer_periodo_ventana,
    case
        when periodo = min(periodo) over (partition by cliente_id_limpio)
        then 'Nuevo'
        else 'Recurrente'
    end as tipo_global
from sin_ocasionales
