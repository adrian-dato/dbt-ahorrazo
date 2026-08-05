-- Reemplaza proc_2_36m.sql (sp_Refrescar_Ventas_36_Ult_Meses_Pivotado).
--
-- Diferencias clave respecto al procedimiento original:
--   - El PIVOT ... FOR pdv_id IN ([3],[5],[6]) hardcodeaba los ids de
--     sucursal. Acá el mapeo pdv_id -> SL/R1/R2 sale del seed
--     dim_sucursal_mapeo -- agregar/cambiar una sucursal es editar el
--     seed, no tocar este SQL (aunque agregar una 4ta columna de salida
--     sí requiere tocar el SQL, eso no lo evita ningún enfoque estándar
--     sin pivot dinámico).
--   - `table` (no incremental): se reconstruye completo en cada corrida,
--     pero a partir de fct_ventas_36m (ya chico, mantenido
--     incrementalmente) -- no repite el escaneo de Ventas_Ahorrazo.
--     dbt hace el swap atómico al final igual que con cualquier `table`.
--     Si el volumen crece y esto se vuelve el cuello de botella, se
--     puede pasar a incremental después (delete+insert por
--     cliente_id_limpio/anio/mes, mismo patrón que fct_ventas_36m).
--   - El proc original filtra cliente_id_limpio IS NOT NULL AND <> '' --
--     ya no hace falta acá: fct_ventas_36m nunca produce esos casos
--     (viene de un INNER JOIN contra clientes ya mapeados).

{{ config(materialized='table') }}

with ventas_agrupadas as (
    select
        cliente_id_limpio,
        anio,
        mes,
        pdv_id,
        sum(total_ventas) as total_ventas
    from {{ ref('fct_ventas_36m') }}
    group by cliente_id_limpio, anio, mes, pdv_id
),

sucursales as (
    select * from {{ ref('dim_sucursal_mapeo') }}
),

pivotado as (
    select
        v.cliente_id_limpio,
        v.anio,
        v.mes,
        sum(case when s.sucursal_codigo = 'SL' then v.total_ventas else 0 end) as SL,
        sum(case when s.sucursal_codigo = 'R1' then v.total_ventas else 0 end) as R1,
        sum(case when s.sucursal_codigo = 'R2' then v.total_ventas else 0 end) as R2
    from ventas_agrupadas v
    inner join sucursales s
        on v.pdv_id = s.pdv_id
    group by v.cliente_id_limpio, v.anio, v.mes
)

select
    p.cliente_id_limpio,
    p.anio,
    p.mes,
    p.SL,
    p.R1,
    p.R2,
    c.nombre
from pivotado p
left join {{ ref('stg_clientes_limpio') }} c
    on p.cliente_id_limpio = c.cliente_id_limpio
