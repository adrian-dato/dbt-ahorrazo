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
    -- IQR efectivo, expuesto para poder reproducir el corte a mano. Cuando
    -- Q1 y Q3 son iguales el IQR real da 0; acá se muestra Q3 en su lugar,
    -- así el valor sigue siendo positivo y comparable con las otras
    -- unidades. Desde que el corte de abajo dejó de depender de esta
    -- columna en el caso IQR=0 (ver umbral_ticket_grande), esta es
    -- puramente informativa en ese caso: ya no entra en la cuenta del
    -- corte.
    --
    -- Q3 no puede dar 0 acá: int_mayoristas_v3_tickets_por_unidad ya
    -- descarta los tickets con unidades <= 0.
    case
        when q3 - q1 <= 0 then q3
        else q3 - q1
    end as iqr_aplicado,
    -- El corte de "factura grande" es Q3 + 3xIQR cuando el IQR real
    -- (q3 - q1) es positivo. Para comparar: en Unid el corte da 67 contra
    -- un Q3 de 19, tres veces y media más arriba -- un corte de outlier de
    -- verdad.
    --
    -- Cuando el IQR real da 0 esa fórmula deja de significar eso: es el
    -- caso de Pack, donde Q1 y Q3 valen los dos 1 (tres de cada cuatro
    -- facturas llevan un solo pack). Sustituir el IQR por Q3 y aplicar la
    -- misma fórmula daba 4xQ3, una proporción elegida solo para no perder
    -- el corte, sin relación con lo que separa una factura grande de una
    -- normal en esa unidad. En su lugar, cuando el IQR real es 0 el corte
    -- pasa a ser 2xQ3 directamente: el doble de lo que ya es una factura
    -- típica de esa unidad. Para Pack, Q3 = 1, así que el corte queda en 2.
    case
        when q3 - q1 <= 0 then 2 * q3
        else q3 + 3 * (q3 - q1)
    end as umbral_ticket_grande
from cuartiles
