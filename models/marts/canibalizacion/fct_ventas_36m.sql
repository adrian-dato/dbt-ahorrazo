-- Reemplaza proc_1_36m.sql (sp_Refrescar_Ventas_36_Ult_Meses_Agrupado).
--
-- Diferencias clave respecto al procedimiento original:
--   - Incremental (delete+insert por partición cliente/producto/pdv/año/mes)
--     en vez de TRUNCATE + INSERT completo: la corrida normal solo
--     reprocesa los últimos `dias_lookback_incremental` días, no los 36
--     meses enteros. El full-scan completo solo ocurre con --full-refresh.
--   - El cast de cliente_id y la collation de categorías se resuelven una
--     sola vez en stg_clientes_mapeo/stg_productos, no en cada corrida.
--   - dbt materializa en una tabla nueva y hace el swap al final: la
--     ventana de bloqueo para lectores concurrentes pasa de "toda la
--     corrida" a segundos.
--
-- Nota de reglas de exclusión: por ahora estas condiciones quedan igual
-- que en el proc original (portado 1:1). Se reemplazan por
-- ref('int_ventas_elegibles') en la Fase 3, cuando ese modelo compartido
-- exista -- no se duplica la lógica mientras tanto, se marca acá.
--
-- Ventana en MESES CERRADOS (corregido -- antes usaba getdate() directo
-- como límite superior, mezclando el mes en curso, parcial, con meses ya
-- cerrados). Mismo criterio que int_ventas_12m/fecha_corte_mes_cerrado().
-- El lookback de abajo (dias_lookback_incremental) es un mecanismo
-- distinto -- cuánto reprocesar para capturar datos que llegan tarde --,
-- no la ventana de reporte en sí, y sigue usando getdate() a propósito.

{{
    config(
        materialized='incremental',
        unique_key=['cliente_id_limpio', 'producto_id', 'pdv_id', 'anio', 'mes'],
        incremental_strategy='delete+insert'
    )
}}

with clientes as (
    select * from {{ ref('stg_clientes_mapeo') }}
),

productos as (
    select * from {{ ref('stg_productos') }}
),

ventas as (
    select *
    from {{ ref('stg_ventas') }}
    where fecha_venta >= dateadd(month, -{{ var('meses_ventana_canibalizacion') }}, {{ fecha_corte_mes_cerrado() }})
      and fecha_venta <  {{ fecha_corte_mes_cerrado() }}
      {% if is_incremental() %}
      -- Lookback: cubre datos que llegan tarde al mes en curso o al
      -- anterior, sin reprocesar los 36 meses completos en cada corrida.
      and fecha_venta >= dateadd(day, -{{ var('dias_lookback_incremental') }}, getdate())
      {% endif %}
)

select
    c.cliente_id_limpio,
    v.producto_id,
    v.pdv_id,
    year(v.fecha_venta)  as anio,
    month(v.fecha_venta) as mes,
    sum(v.venta_gs)      as total_ventas
from ventas v
inner join clientes c
    on v.cliente_id = c.cliente_id
inner join productos p
    on v.producto_id = p.producto_id
where
    -- Exclusión histórica de un cliente interno/de test — regla heredada
    -- de proc_1_36m.sql, no un ID real de negocio.
    isnull(c.cliente_id_limpio, '') <> '44444401'
    and p.id_empresa = 3
    and isnull(p.categoria_2, '') not like '%bolsa%'
    and isnull(p.categoria_1, '') not like '%egre%'
    and isnull(p.categoria_1, '') not like '%servi%'
group by
    c.cliente_id_limpio,
    v.producto_id,
    v.pdv_id,
    year(v.fecha_venta),
    month(v.fecha_venta)
