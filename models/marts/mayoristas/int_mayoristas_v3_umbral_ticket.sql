-- Los cortes de "factura grande" por unidad de medida: Q1, Q3, el IQR
-- que entra en la cuenta y el umbral que sale de ellos. Cuatro filas.
--
-- POR QUE ESTO ESTA EN SU PROPIO ARCHIVO Y NO ADENTRO DE
-- mayoristas_v3_tickets_unidad, que es donde estaba antes.
--
-- Un `with x as (...)` no guarda el resultado: solo le pone nombre a una
-- consulta. Cada vez que se escribe ese nombre, SQL Server vuelve a
-- ejecutar la consulta entera desde cero. No hay forma de decirle "esto
-- ya lo calculaste, reusalo".
--
-- Si el calculo de los cortes viviera en el mismo archivo que la tabla de
-- facturas, la agrupacion de las 62 millones de lineas en 7,4 millones de
-- facturas aparecería cinco veces: una por cada unidad de medida para
-- sacar su percentil, mas una vez mas para el resultado final. O sea que
-- ese unico archivo agruparia 62 millones de lineas cinco veces para
-- producir una sola tabla. Eso colgo la instancia, dos veces.
--
-- Partido en dos, la agrupacion se hace una vez, queda guardada en
-- int_mayoristas_v3_tickets_por_unidad, y las cinco lecturas siguientes
-- son contra 7,4 millones de filas ya agrupadas.
--
-- El beneficio de sacarlo aca y no dejarlo donde estaba: como este archivo
-- devuelve 4 filas, mayoristas_v3_tickets_unidad ya no necesita ser una
-- tabla y pasa a ser una vista. Antes los mismos 7,4 millones de filas
-- estaban guardados dos veces.
--
-- Las 4 unidades van en ramas separadas con UNION ALL, no con
-- PERCENTILE_CONT(...) OVER (PARTITION BY unidad_medida). La distribución
-- entre unidades es muy despareja (Unid + KILOS son >99% de los tickets),
-- y particionar la ventana por esa columna fuerza al motor a repartir el
-- trabajo paralelo por ahí, dejando 2-3 threads cargando casi todas las
-- filas mientras el resto queda ocioso -- esto tumbó la instancia dos
-- veces. Separado por rama, cada unidad se paraleliza libre por su
-- cuenta. Resultado idéntico al de la ventana.
--
-- El OVER() vacío es obligatorio: a diferencia de Postgres/Oracle,
-- PERCENTILE_CONT en T-SQL solo existe como función de ventana, nunca
-- como agregado con GROUP BY (falla con el error 10753 sin OVER). No es
-- un PARTITION BY -- cada rama ya viene filtrada a una sola unidad, así
-- que OVER() vacío es "toda la rama es la partición". El DISTINCT colapsa
-- las filas repetidas.

{{ config(materialized='table') }}

{% set unidades_relevantes = ['Unid', 'KILOS', 'LITROS', 'Pack'] %}

with cuartiles as (
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
    unidad_medida,
    q1 as q1_unidades,
    q3 as q3_unidades,
    q3 - q1 as iqr_unidades,
    -- IQR efectivo. Cuando Q1 y Q3 son iguales el IQR da 0 y la fórmula
    -- Q3 + 3xIQR colapsa a Q3 -- el corte deja de significar "muy por
    -- encima del grueso" y pasa a significar "arriba del percentil 75",
    -- que es otra cosa y mucho más fácil de cumplir. Para comparar: en
    -- Unid el corte da 67 contra un Q3 de 19, tres veces y media más
    -- arriba; en Pack, con IQR 0, corte y Q3 eran el mismo número (1).
    --
    -- En ese caso se usa Q3 en lugar del IQR, así el corte queda en 4xQ3
    -- y conserva la proporción de las otras unidades en vez de
    -- desaparecer. Para Pack: 1 + 3x1 = 4, o sea que una factura de packs
    -- cuenta como grande a partir de 5.
    --
    -- Q3 no puede dar 0 acá: int_mayoristas_v3_tickets_por_unidad ya
    -- descarta los tickets con unidades <= 0, así que el fallback nunca
    -- deja el corte en cero.
    case
        when q3 - q1 <= 0 then q3
        else q3 - q1
    end as iqr_aplicado,
    q3 + 3 * case
                when q3 - q1 <= 0 then q3
                else q3 - q1
             end as umbral_ticket_grande
from cuartiles
