-- Para qué sirve este modelo: grano factura (ticket) -- responde "¿por
-- qué ESTA factura puntual de este cliente contó (o no) como 'ticket
-- grande'?", que es lo que un analista necesita para justificar la
-- clasificación de un cliente puntual, no un promedio mensual que ya
-- perdió el detalle de la factura individual. Es el insumo de
-- mayoristas_v3_detalle_unidad/mayoristas_v3_resumen (agregan esto por
-- cliente), y a la vez la fuente directa de la página "historial de
-- facturas" del tablero de Power BI -- no hace falta bajar a línea de
-- producto (esa consulta, si hace falta puntual, es un drillthrough
-- aparte contra int_ventas_elegibles filtrado a 1 ticket_id, no este
-- modelo).
--
-- Primer modelo de la metodología v3 (eventos por unidad_medida) que se
-- porta a dbt de verdad -- hasta ahora vivía entero en
-- analisis_mayorista/analisis_mayoristas_v3.ipynb, escribiendo a mano a
-- marts_mayoristas.mayoristas_v3_* vía pandas. El notebook pasa a leer
-- de acá (ref a este modelo) en vez de recalcular esto mismo en Python
-- -- una sola fuente de verdad para "unidades/venta por ticket y si es
-- grande", no dos que puedan desalinearse.
--
-- IMPORTANTE -- todavía prototipo, no reemplaza a
-- int_mayoristas_umbral_ticket_grande/int_mayoristas_metricas_cliente
-- (v2, con el bug de unidad_medida mezclada sin corregir, ver
-- PENDIENTES.md) -- esos siguen siendo la fuente de producción hasta
-- que v3 se valide y se decida el cutover.
--
-- Por qué solo Unid/KILOS/LITROS/Pack (no Blis/Metros/Ramo): las otras
-- 3 no tienen volumen ni variancia real -- la gran mayoría de esos
-- tickets son "1 unidad", siempre (mediana=Q1=Q3=1) -- no hay ningún
-- corte que separe "grande" de "normal" ahí. Confirmado contra datos
-- reales, no supuesto -- ver el boxplot por unidad_medida en el
-- notebook.
--
-- umbral_ticket_grande = Q3 + 3xIQR de unidades por ticket, calculado
-- POR SEPARADO en cada unidad_medida (PARTITION BY en el PERCENTILE_CONT
-- de abajo) -- a diferencia de int_mayoristas_umbral_ticket_grande (v2),
-- que calcula un único umbral global mezclando todas las unidades, este
-- es el fix central de v3. El multiplicador es 3 (no el 1.5 que usa
-- v2) -- decisión explícita del usuario, ver PENDIENTES.md.

{{ config(materialized='table') }}

with tickets_por_unidad as (
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
),

-- PERCENTILE_CONT en SQL Server es una función de ventana (necesita
-- OVER()), no un agregado simple -- con PARTITION BY unidad_medida da
-- el mismo par (q1, q3) repetido en cada fila de esa unidad, por eso el
-- DISTINCT para quedarse con 1 fila por unidad_medida.
umbrales as (
    select distinct
        unidad_medida,
        percentile_cont(0.25) within group (order by unidades) over (partition by unidad_medida) as q1,
        percentile_cont(0.75) within group (order by unidades) over (partition by unidad_medida) as q3
    from tickets_por_unidad
)

select
    t.cliente_id_limpio,
    t.ticket_id,
    t.unidad_medida,
    t.fecha_venta,
    t.unidades,
    t.venta_gs,
    u.q3 + 3 * (u.q3 - u.q1) as umbral_ticket_grande,
    case
        when t.unidades > u.q3 + 3 * (u.q3 - u.q1) then 1
        else 0
    end as ticket_grande
from tickets_por_unidad t
inner join umbrales u
    on t.unidad_medida = u.unidad_medida
