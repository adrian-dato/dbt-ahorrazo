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
-- Fuente de producción desde el cutover. Los modelos de la v2 que
-- calculaban un umbral único mezclando todas las unidades de medida ya
-- no existen en el proyecto.
--
-- Por qué solo Unid/KILOS/LITROS/Pack (no Blis/Metros/Ramo): las otras
-- 3 no tienen volumen ni variancia real -- la gran mayoría de esos
-- tickets son "1 unidad", siempre (mediana=Q1=Q3=1) -- no hay ningún
-- corte que separe "grande" de "normal" ahí. Confirmado contra datos
-- reales, no supuesto -- ver el boxplot por unidad_medida en el
-- notebook.
--
-- umbral_ticket_grande = Q3 + 3xIQR de unidades por ticket, calculado
-- POR SEPARADO en cada unidad_medida -- a diferencia de la v2, que
-- calculaba un único umbral global mezclando todas las unidades, este es
-- el fix central de v3. El multiplicador es 3 y no el 1,5 estándar de
-- outlier, por decisión explícita del negocio. Excepción: cuando el IQR
-- real da 0 (Q1 = Q3, el caso de Pack) el corte no sale de esa fórmula
-- sino de 2xQ3 directo -- ver el caso Q1 = Q3 en el CTE umbrales de
-- int_mayoristas_v3_umbral_ticket.
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

{{ config(materialized='view') }}

-- VISTA, no tabla. Es int_mayoristas_v3_tickets_por_unidad con los cortes
-- pegados al lado: 4 columnas constantes por unidad de medida y un CASE.
-- Materializarla guardaba los mismos 7,4 millones de filas dos veces, y
-- la unica razon para hacerlo era que el calculo del percentil vivia aca
-- adentro. Ese calculo se mudo a int_mayoristas_v3_umbral_ticket, que
-- devuelve 4 filas, asi que el join es contra una tabla minuscula y la
-- vista se resuelve barata.

select
    t.cliente_id_limpio,
    t.ticket_id,
    t.unidad_medida,
    t.fecha_venta,
    t.unidades,
    t.venta_gs,
    -- Q1, Q3 y el IQR que realmente se uso viajan con cada fila. Sin los
    -- numeros de origen nadie puede reproducir el corte con otra
    -- herramienta, y quien rehaga la cuenta con q1 y q3 a mano obtiene 1
    -- para Pack en vez de 2 y concluye que el modelo esta mal.
    u.q1_unidades,
    u.q3_unidades,
    u.iqr_aplicado,
    u.umbral_ticket_grande,
    case
        when t.unidades > u.umbral_ticket_grande then 1
        else 0
    end as ticket_grande
from {{ ref('int_mayoristas_v3_tickets_por_unidad') }} t
inner join {{ ref('int_mayoristas_v3_umbral_ticket') }} u
    on t.unidad_medida = u.unidad_medida
