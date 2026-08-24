-- Para qué sirve este modelo: grano factura (ticket) -- responde "¿por
-- qué ESTA factura puntual de este cliente contó (o no) como 'ticket
-- grande'?", que es lo que un analista necesita para justificar la
-- clasificación de un cliente puntual, no un promedio mensual que ya
-- perdió el detalle de la factura individual. Es el insumo de
-- mayoristas_v3_metricas_unidad (agrega esto por cliente), y a la vez
-- la fuente directa de la página "historial de
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
-- POR SEPARADO en cada unidad_medida -- a diferencia de
-- int_mayoristas_umbral_ticket_grande (v2), que calcula un único umbral
-- global mezclando todas las unidades, este es el fix central de v3. El
-- multiplicador es 3 (no el 1.5 que usa v2) -- decisión explícita del
-- usuario, ver PENDIENTES.md.
--
-- Q1/Q3 se calculan en ramas separadas por unidad_medida (UNION ALL),
-- no con PERCENTILE_CONT(...) OVER (PARTITION BY unidad_medida): la
-- distribución entre las 4 unidades es muy despareja (Unid + KILOS son
-- >99% de los tickets), y particionar la ventana por esa columna fuerza
-- al motor a repartir el trabajo paralelo por ahí, dejando 2-3 threads
-- cargando casi todas las filas mientras decenas de otros quedan
-- ociosos -- esto tumbó la base la primera vez que corrió. Separado por
-- rama, cada unidad_medida se paraleliza libre por su cuenta. Resultado
-- idéntico al de la ventana: misma fórmula, mismas filas de entrada por
-- unidad, solo cambia cómo el motor llega al número.
--
-- El OVER() vacío es obligatorio -- a diferencia de Postgres/Oracle,
-- PERCENTILE_CONT en T-SQL solo existe como función de ventana, nunca
-- como agregado simple con GROUP BY (falla con el error 10753 sin
-- OVER). No es un PARTITION BY: cada rama ya viene filtrada a una sola
-- unidad_medida, así que OVER() vacío es "toda la rama es la
-- partición" -- no reintroduce la columna despareja. El DISTINCT
-- colapsa las filas repetidas (mismo valor en cada fila de la rama).

{{ config(materialized='table') }}

{% set unidades_relevantes = ['Unid', 'KILOS', 'LITROS', 'Pack'] %}

with umbrales as (
    {% for u in unidades_relevantes %}
    select distinct
        '{{ u }}' as unidad_medida,
        percentile_cont(0.25) within group (order by unidades) over () as q1,
        percentile_cont(0.75) within group (order by unidades) over () as q3
    from {{ ref('int_mayoristas_v3_tickets_por_unidad') }}
    where unidad_medida = '{{ u }}'
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
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
from {{ ref('int_mayoristas_v3_tickets_por_unidad') }} t
inner join umbrales u
    on t.unidad_medida = u.unidad_medida
