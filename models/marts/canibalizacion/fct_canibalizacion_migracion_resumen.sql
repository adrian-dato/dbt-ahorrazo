-- Reemplaza el paso 11 de canibalizacion_v3.py (df_salida): resumen
-- agregado por (anio, mes, tipo_cliente, local_origen, local_destino) --
-- SIN cliente_id_limpio, para reportes de distribución/totales. Mismo
-- grano final que el script escribe hoy a dbo.canibalizacion_sucursales.

{{ config(materialized='table') }}

select
    anio,
    mes,
    tipo_cliente,
    local_origen,
    local_destino,
    count(cliente_id_limpio) as cantidad_clientes,
    sum(monto_total)         as monto_total
from {{ ref('dim_cliente_migracion_eventos') }}
group by anio, mes, tipo_cliente, local_origen, local_destino
