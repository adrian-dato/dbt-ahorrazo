-- Reemplaza el paso 7 de canibalizacion_v3.py (melt a formato largo,
-- df_largo): grano cliente×mes×sucursal, TODOS los clientes de la
-- ventana. A diferencia del script, esto SE PERSISTE como tabla final
-- de una vez (el script lo calculaba como paso intermedio y lo
-- descartaba, hasta que se agregó la tabla evolutivo por separado) --
-- acá es a la vez insumo de dim_cliente_migracion_eventos y el output
-- para el visual de PowerBI del evolutivo mensual por cliente.

{{ config(materialized='table') }}

with base as (
    select * from {{ ref('int_canibalizacion_migracion_base') }}
)

select
    cliente_id_limpio, nombre, anio, mes, periodo,
    'SL' as sucursal, SL as monto, tipo_global, primer_periodo_ventana
from base
where SL > 0

union all

select
    cliente_id_limpio, nombre, anio, mes, periodo,
    'R1' as sucursal, R1 as monto, tipo_global, primer_periodo_ventana
from base
where R1 > 0

union all

select
    cliente_id_limpio, nombre, anio, mes, periodo,
    'R2' as sucursal, R2 as monto, tipo_global, primer_periodo_ventana
from base
where R2 > 0
