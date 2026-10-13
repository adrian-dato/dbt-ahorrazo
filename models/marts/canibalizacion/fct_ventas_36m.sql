-- Reemplaza proc_1_36m.sql (sp_Refrescar_Ventas_36_Ult_Meses_Agrupado).
--
-- Diferencias clave respecto al procedimiento original:
--   - Incremental (delete+insert por partición cliente/producto/pdv/año/mes)
--     en vez de TRUNCATE + INSERT completo: la corrida normal solo
--     reprocesa los últimos `meses_lookback_incremental` meses cerrados,
--     no los 36 enteros. El full-scan completo solo ocurre con --full-refresh.
--   - dbt materializa en una tabla nueva y hace el swap al final: la
--     ventana de bloqueo para lectores concurrentes pasa de "toda la
--     corrida" a segundos.
--
-- Usa ref('int_ventas_elegibles') para las reglas de exclusión
-- (empresa/categoría/cliente test/producto excluido) en vez de la copia
-- inline que tenía antes -- cierra la duplicación que había quedado
-- pendiente. CAMBIO DE RESULTADO real,
-- no solo de código: int_ventas_elegibles también excluye los 13
-- producto_id de seeds/productos_excluidos.csv (ids de test/placeholder),
-- regla que hasta ahora solo aplicaba a Top 300. Confirmado con el
-- usuario antes de aplicar.
--
-- Ventana en MESES CERRADOS (corregido -- antes usaba getdate() directo
-- como límite superior, mezclando el mes en curso, parcial, con meses ya
-- cerrados). Mismo criterio que int_ventas_12m/fecha_corte_mes_cerrado().
--
-- El lookback incremental arranca el día 1 de un mes, nunca a mitad. La
-- clave agrupa por mes, y delete+insert reemplaza la fila entera de esa
-- clave: con un lookback en días (antes 45) la suma recalculada cubría
-- solo el tramo final del mes más viejo y pisaba el total real de ese mes
-- con un monto parcial. Reprocesar meses completos hace que cada fila
-- reemplazada tenga el mes entero.

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
      -- Lookback: los últimos meses cerrados completos, para capturar
      -- ventas que llegan tarde sin reprocesar los 36 meses.
      and fecha_venta >= dateadd(month, -{{ var('meses_lookback_incremental') }}, {{ fecha_corte_mes_cerrado() }})
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
