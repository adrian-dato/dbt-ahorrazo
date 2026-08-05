-- Comparación legacy (dbo.clientes_mapeo / dbo.clientes_limpio, generadas
-- por clientes_mapeo_limpio.sql) vs. nuevo (int_clientes_mapeo_limpio /
-- int_clientes_limpio), para correr manualmente antes de repointear
-- stg_clientes_mapeo / stg_clientes_limpio al nuevo proceso.
--
-- No es un modelo (no corre con `dbt build`): compilar con
-- `dbt compile --select validar_clientes_mapeo_limpio` y correr el SQL
-- resultante a mano, o `dbt show` si la versión de dbt lo soporta.
--
-- IMPORTANTE: a diferencia de una migración 1:1, acá SÍ se esperan
-- diferencias -- int_clientes_mapeo_limpio corrige a propósito casos que
-- el legacy resolvía mal (ver el comentario al principio de
-- int_clientes_mapeo_limpio.sql para el detalle). Lo que hay que mirar:
--
--   - `conteo_solo_nuevo` en 0 siempre: el nuevo proceso nunca debería
--     mapear un cliente_id que el legacy no tenía -- si esto es > 0, es
--     un bug real, no una mejora esperada.
--   - `conteo_solo_legacy` > 0 es ESPERADO: son los clientes no
--     identificables (cliente_id sin ningún dígito, ej. un nombre de
--     persona) que ahora se excluyen a propósito.
--   - `conteo_valor_distinto` > 0 es ESPERADO para los casos con símbolos
--     sueltos en los extremos o separadores no estándar (`|`, `,`, `_`,
--     `/` con un solo dígito al final) -- el nuevo debería dar el id
--     "bien" limpio, el legacy uno con basura pegada.
--
-- Para no confiar solo en los conteos, correr la sección 2 de abajo
-- (comentada) y mirar una muestra real de las filas que difieren --
-- confirmar que cada diferencia encaja en alguno de los patrones de
-- arriba, no algo inesperado.

with legacy as (
    select cliente_id, cliente_id_limpio
    from {{ source('dato_solutions', 'clientes_mapeo') }}
),

nuevo as (
    select cliente_id, cliente_id_limpio
    from {{ ref('int_clientes_mapeo_limpio') }}
),

comparacion as (
    select
        coalesce(l.cliente_id, n.cliente_id) as cliente_id,
        l.cliente_id_limpio as cliente_id_limpio_legacy,
        n.cliente_id_limpio as cliente_id_limpio_nuevo
    from legacy l
    full outer join nuevo n
        on l.cliente_id = n.cliente_id
)

-- 1) Resumen de conteos
select
    count(*)                                                              as total_filas_comparadas,
    sum(case when cliente_id_limpio_nuevo is null then 1 else 0 end)      as conteo_solo_legacy,
    sum(case when cliente_id_limpio_legacy is null then 1 else 0 end)     as conteo_solo_nuevo,
    sum(case
            when cliente_id_limpio_legacy is not null
             and cliente_id_limpio_nuevo is not null
             and cliente_id_limpio_legacy <> cliente_id_limpio_nuevo
            then 1 else 0
        end)                                                              as conteo_valor_distinto
from comparacion

-- 2) Para inspeccionar filas concretas, comentar el SELECT de arriba y
--    correr uno de estos:
--
-- select cliente_id, cliente_id_limpio_legacy, cliente_id_limpio_nuevo
-- from comparacion
-- where cliente_id_limpio_legacy is not null and cliente_id_limpio_nuevo is not null
--   and cliente_id_limpio_legacy <> cliente_id_limpio_nuevo;
--
-- select cliente_id, cliente_id_limpio_legacy
-- from comparacion
-- where cliente_id_limpio_nuevo is null and cliente_id_limpio_legacy is not null;
-- (estos son los excluidos por no identificables -- confirmar que
--  cliente_id_limpio_legacy en estas filas es texto/nombre, no un
--  documento real que se esté descartando por error)
--
-- select cliente_id, cliente_id_limpio_nuevo
-- from comparacion
-- where cliente_id_limpio_legacy is null and cliente_id_limpio_nuevo is not null;
-- (esto SIEMPRE debería devolver 0 filas -- si aparece algo, es un bug)
