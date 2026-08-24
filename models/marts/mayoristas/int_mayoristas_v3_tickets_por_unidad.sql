-- Grano cliente_id_limpio x ticket_id x unidad_medida -- agregación base
-- para el cálculo de umbrales v3 (Q1/Q3 por unidad_medida en
-- mayoristas_v3_tickets_unidad). Separado en su propio modelo (en vez de
-- vivir como CTE ahí) para que el GROUP BY sobre las ~62M filas de
-- int_ventas_12m se calcule una sola vez -- mayoristas_v3_tickets_unidad
-- necesita leer este resultado 5 veces (una por unidad_medida para el
-- umbral, más el join final), y sin materializarlo aparte cada
-- referencia recalcularía la agregación completa desde cero.

{{ config(materialized='table') }}

select
    v.cliente_id_limpio,
    v.ticket_id,
    p.unidad_medida,
    min(v.fecha_venta) as fecha_venta,  -- 1 sola fecha real por ticket, min() solo por sintaxis de group by
    sum(v.unidades)    as unidades,
    sum(v.venta_gs)    as venta_gs
from {{ ref('int_ventas_12m') }} v
inner join {{ ref('int_productos_limpio') }} p
    on v.producto_id = p.producto_id
where p.unidad_medida in ('Unid', 'KILOS', 'LITROS', 'Pack')
group by v.cliente_id_limpio, v.ticket_id, p.unidad_medida
having sum(v.unidades) > 0  -- excluye devoluciones, mismo criterio que el resto del proyecto
