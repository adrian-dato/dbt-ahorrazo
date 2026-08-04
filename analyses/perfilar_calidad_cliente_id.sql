-- Perfilado de calidad de dato sobre cliente_id crudo (dbo.Clientes +
-- huérfanos de Ventas_Ahorrazo), INDEPENDIENTE de si el proceso legacy
-- (clientes_mapeo_limpio.sql) lo resuelve bien o mal -- nunca se
-- confirmó con certeza que esa heurística sea correcta, así que no sirve
-- de referencia. Este perfilado mira los datos crudos directamente.
--
-- No es un modelo (no corre con `dbt build`): compilar con
-- `dbt compile --select perfilar_calidad_cliente_id` y correr el SQL
-- resultante a mano contra la base real.
--
-- Qué buscar en el resultado de la sección 1 (resumen):
--   - `con_otros_caracteres`: ids con algún caracter que la limpieza
--     actual NO trata (ni espacio/tab/letra, ni '-'/'*'). Ej. '.', '/',
--     '_', '+'. Estos NO se separan como "444443-2" -> "444443" -- el
--     caracter sobrevive tal cual en cliente_id_limpio, generando un
--     id_limpio distinto por cada variante en vez de colapsar al mismo
--     cliente. Si este número es alto, la heurística legacy se queda
--     corta, no solo el port a dbt.
--   - `con_guion_y_asterisco`: ids con AMBOS '-' y '*' -- la regla
--     original prioriza '-' (lo revisa primero). Si hay casos reales acá,
--     vale confirmar si esa prioridad es la correcta o si hace falta
--     una regla distinta para ese patrón.
--   - `queda_vacio_tras_limpiar`: ids que, tras la limpieza, quedan en
--     cadena vacía y caen al fallback (usar el id original sin limpiar)
--     -- candidatos a revisar manualmente, uno por uno si son pocos.

with clientes_crudos as (
    select cast(cliente_id as varchar(255)) as cliente_id
    from {{ source('dato_solutions', 'Clientes') }}
    where cliente_id is not null

    union

    select cast(cliente_id as varchar(255))
    from {{ source('dato_solutions', 'Ventas_Ahorrazo') }}
    where cliente_id is not null
),

clasificado as (
    select
        cliente_id,
        {{ limpiar_id('cliente_id') }} as cliente_id_clean,
        case when cliente_id like '%[-]%' then 1 else 0 end as tiene_guion,
        case when cliente_id like '%[*]%' then 1 else 0 end as tiene_asterisco,
        -- cualquier caracter que NO sea letra/dígito/espacio/tab/CR/LF/'-'/'*'
        case
            when cliente_id like '%[^A-Za-z0-9 ' + char(9) + char(10) + char(13) + '*-]%'
                then 1 else 0
        end as tiene_otro_caracter
    from clientes_crudos
)

-- 1) Resumen general
select
    count(*)                                                          as total_ids,
    sum(tiene_guion)                                                  as con_guion,
    sum(tiene_asterisco)                                              as con_asterisco,
    sum(case when tiene_guion = 1 and tiene_asterisco = 1 then 1 else 0 end) as con_guion_y_asterisco,
    sum(tiene_otro_caracter)                                          as con_otros_caracteres,
    sum(case when cliente_id_clean = '' then 1 else 0 end)            as queda_vacio_tras_limpiar
from clasificado

-- 2) Para inspeccionar casos concretos, comentar el SELECT de arriba y
--    correr uno de estos (ajustar TOP según cuántos casos haya):
--
-- select top 50 cliente_id, cliente_id_clean from clasificado where tiene_otro_caracter = 1;
-- select top 50 cliente_id, cliente_id_clean from clasificado where tiene_guion = 1 and tiene_asterisco = 1;
-- select top 50 cliente_id from clasificado where cliente_id_clean = '';

-- 3) Histograma real de colisiones (cuántos cliente_id distintos
--    colapsan a cada cliente_id_limpio) -- correr por separado, requiere
--    que int_clientes_mapeo_limpio ya esté construido en la base:
--
-- select
--     cantidad_ids_origen,
--     count(*) as cantidad_de_clientes_con_esa_cantidad
-- from (
--     select cliente_id_limpio, count(distinct cliente_id) as cantidad_ids_origen
--     from {{ ref('int_clientes_mapeo_limpio') }}
--     group by cliente_id_limpio
-- ) t
-- group by cantidad_ids_origen
-- order by cantidad_ids_origen desc;
