-- Reemplaza clientes_mapeo_limpio.sql (sp_refresh_clientes_mapeo_limpio),
-- pasos A+B+C: construcción del mapeo cliente_id -> cliente_id_limpio.
--
-- Diferencias clave respecto al proceso legacy:
--   - Ya no vive dentro de una única transacción de ~1h+ (BEGIN TRAN sin
--     COMMIT hasta el final) que bloquea clientes_mapeo/clientes_limpio
--     -- y por lo tanto a los 3 proyectos que las consumen -- durante
--     todo el runtime. dbt materializa en un objeto nuevo y hace el
--     swap al final.
--   - Incremental: la detección de cliente_id "huérfanos" (que aparecen
--     en Ventas_Ahorrazo pero no en Clientes -- paso B del proceso
--     legacy) ya no escanea los 238M+ registros completos en cada
--     corrida, solo los últimos `dias_lookback_incremental` días. Un
--     cliente cuya ÚNICA venta histórica sea más antigua que esa
--     ventana no se detectaría hasta un `--full-refresh`; mismo
--     trade-off ya aceptado en fct_ventas_36m, documentado acá también.
--     El lado de Clientes (paso A) sí se recalcula completo en cada
--     corrida -- es una tabla chica, no la fuente del cuello de botella.
--
-- Cadencia: este modelo alimenta a los 3 proyectos, y los más exigentes
-- (Canibalización, Top 300) tienen SLA semanal -- así que el mapeo de
-- clientes tiene que estar al menos igual de fresco. El lookback de 45
-- días se calcula contra `getdate()` (el momento de la corrida), no
-- contra la fecha de la última corrida exitosa -- por eso una cadencia
-- semanal queda cubierta con ~6x de margen (6 corridas atrás), sin
-- necesidad de trackear estado entre corridas: si una corrida semanal se
-- atrasa o se salta una semana, la siguiente corrida igual re-cubre todo
-- el período sin dejar un hueco de clientes sin mapear. El valor (45)
-- es el mismo ya validado en `dias_lookback_incremental` para
-- fct_ventas_36m en canibalizacion_ahorrazo, que ya opera semanal --
-- no es un número nuevo sin evidencia detrás.
--
-- unique_key = cliente_id: 1 fila por cliente_id, igual que el índice
-- único CX_clientes_mapeo_cliente_id del proceso legacy.
--
-- Nota: todavía NO reemplaza a stg_clientes_mapeo -- corre en paralelo
-- al proceso legacy hasta validar (ver analyses/validar_clientes_mapeo_limpio.sql)
-- que produce el mismo resultado, antes de que cualquier mart lo consuma.

{{
    config(
        materialized='incremental',
        unique_key='cliente_id',
        incremental_strategy='delete+insert'
    )
}}

with clientes_mapeados as (
    -- Paso A: todo cliente_id que existe en dbo.Clientes.
    select
        cliente_id,
        cliente_id_limpio
    from {{ ref('int_clientes_normalizados') }}
),

ventas_recientes as (
    select distinct cliente_id
    from {{ ref('stg_ventas') }}
    where cliente_id is not null
    {% if is_incremental() %}
    and fecha_venta >= dateadd(day, -{{ var('dias_lookback_incremental') }}, getdate())
    {% endif %}
),

ventas_huerfanas as (
    -- Paso B: cliente_id que aparecen en Ventas_Ahorrazo pero no en
    -- Clientes -- se les asigna cliente_id_limpio con la misma regla,
    -- sin nombre/ci_ruc asociado (no existen en Clientes).
    select v.cliente_id
    from ventas_recientes v
    left join clientes_mapeados m
        on m.cliente_id = v.cliente_id
    where m.cliente_id is null
),

ventas_normalizadas as (
    select
        cliente_id,
        {{ limpiar_id('cliente_id') }} as cliente_id_clean
    from ventas_huerfanas
),

ventas_mapeadas as (
    select distinct
        cliente_id,
        {{ derivar_cliente_id_limpio('cliente_id', 'cliente_id_clean') }} as cliente_id_limpio
    from ventas_normalizadas
),

union_completo as (
    select cliente_id, cliente_id_limpio from clientes_mapeados
    union all
    select cliente_id, cliente_id_limpio from ventas_mapeadas
)

-- Paso C: dedup determinístico -- 1 fila por cliente_id (mismo criterio
-- que el proceso legacy: MIN(cliente_id_limpio), no "el más reciente").
select
    cliente_id,
    min(cliente_id_limpio) as cliente_id_limpio
from union_completo
group by cliente_id
