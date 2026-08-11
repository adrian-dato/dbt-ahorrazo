-- Reemplaza proc_1_36m.sql (sp_Refrescar_Ventas_36_Ult_Meses_Agrupado).
--
-- Diferencias clave respecto al procedimiento original:
--   - Incremental (delete+insert por partición cliente/producto/pdv/año/mes)
--     en vez de TRUNCATE + INSERT completo: la corrida normal solo
--     reprocesa los últimos `dias_lookback_incremental` días, no los 36
--     meses enteros. El full-scan completo solo ocurre con --full-refresh.
--   - dbt materializa en una tabla nueva y hace el swap al final: la
--     ventana de bloqueo para lectores concurrentes pasa de "toda la
--     corrida" a segundos.
--
-- Usa ref('int_ventas_elegibles') para las reglas de exclusión
-- (empresa/categoría/cliente test/producto excluido) en vez de la copia
-- inline que tenía antes -- cierra la duplicación que había quedado
-- pendiente desde Fase 3 (ver PENDIENTES.md). CAMBIO DE RESULTADO real,
-- no solo de código: int_ventas_elegibles también excluye los 13
-- producto_id de seeds/productos_excluidos.csv (ids de test/placeholder),
-- regla que hasta ahora solo aplicaba a Top 300. Confirmado con el
-- usuario antes de aplicar.
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

with ventas as (
    select *
    from {{ ref('int_ventas_elegibles') }}
    where fecha_venta >= dateadd(month, -{{ var('meses_ventana_canibalizacion') }}, {{ fecha_corte_mes_cerrado() }})
      and fecha_venta <  {{ fecha_corte_mes_cerrado() }}
      {% if is_incremental() %}
      -- Lookback: cubre datos que llegan tarde al mes en curso o al
      -- anterior, sin reprocesar los 36 meses completos en cada corrida.
      and fecha_venta >= dateadd(day, -{{ var('dias_lookback_incremental') }}, getdate())
      {% endif %}
)

select
    cliente_id_limpio,
    producto_id,
    pdv_id,
    year(fecha_venta)  as anio,
    month(fecha_venta) as mes,
    sum(venta_gs)      as total_ventas
from ventas
group by
    cliente_id_limpio,
    producto_id,
    pdv_id,
    year(fecha_venta),
    month(fecha_venta)
