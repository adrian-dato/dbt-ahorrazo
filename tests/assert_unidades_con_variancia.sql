{{ config(severity = 'warn') }}

-- Avisa cuando alguna unidad de medida de la metodologia tiene Q1 igual a
-- Q3, o sea IQR crudo 0.
--
-- No es un error: int_mayoristas_v3_umbral_ticket tiene el fallback que en
-- ese caso usa 2xQ3 en lugar de Q3 + 3xIQR, asi que el corte sigue
-- existiendo (para Pack queda en 2, no en 1). Pero conviene verlo en cada
-- corrida, porque una unidad con IQR 0 es una unidad donde casi todos los tickets
-- son iguales, y eso es exactamente la condicion por la que Blis, Metros
-- y Ramo quedaron afuera de C1 y C2 desde el principio.
--
-- Queda en 'warn' a proposito: no rompe el build, avisa. Si aparece una
-- unidad nueva aca, lo que hay que revisar no es el corte sino si esa
-- unidad tiene algo que aportar a la metodologia.

select
    unidad_medida,
    q1_unidades,
    q3_unidades,
    iqr_unidades,
    iqr_aplicado,
    umbral_ticket_grande
from {{ ref('mayoristas_v3_umbrales') }}
where iqr_unidades <= 0
