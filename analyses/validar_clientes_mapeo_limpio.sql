-- Comparación legacy (dbo.clientes_mapeo / dbo.clientes_limpio, generadas
-- por clientes_mapeo_limpio.sql) vs. nuevo (int_clientes_mapeo_limpio /
-- int_clientes_limpio), para correr manualmente antes de repointear
-- stg_clientes_mapeo / stg_clientes_limpio al nuevo proceso.
--
-- No es un modelo (no corre con `dbt build`): compilar con
-- `dbt compile --select validar_clientes_mapeo_limpio` y correr el SQL
-- resultante a mano, o `dbt show` si la versión de dbt lo soporta.
--
-- Se espera:
--   - conteo_solo_legacy / conteo_solo_nuevo en 0 (mismos cliente_id de
--     un lado y del otro).
--   - conteo_valor_distinto en 0 (mismo cliente_id -> mismo cliente_id_limpio
--     en ambos procesos).
-- Cualquier valor > 0 se investiga antes de dar por válida la migración
-- (ver §5 riesgos: "traducciones de lógica sensible introducen diferencias
-- sutiles" es el riesgo más alto de todo el portfolio para este modelo puntual).

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
