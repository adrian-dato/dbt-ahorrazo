-- Compara la regla nueva de tipo_persona (int_clientes_limpio, "8
-- dígitos que empiezan en 8" = todo el rango jurídico real) contra la
-- regla legacy (prefijos '800'/'801'/'802' hardcodeados, de
-- view_ventas_ahorrazo_filtradas_12m) -- antes de reemplazar el CASE
-- legacy en ningún consumidor real.
--
-- No es un modelo: compilar con
-- `dbt compile --select validar_tipo_persona` y correr el SQL
-- resultante a mano, o `dbt show --select validar_tipo_persona`.
--
-- Lo esperado: la regla nueva puede marcar 'Juridico' algunos
-- cliente_id_limpio que la legacy marcaba 'Fisico' -- son los
-- prefijos 803/804/etc. que la SET asignó después de que se escribiera
-- el CASE original (ver comentario de int_clientes_limpio.sql). Si
-- aparecen diferencias en el otro sentido (nuevo dice 'Fisico', legacy
-- decía 'Juridico'), o diferencias fuera del rango 803-899, eso sí
-- amerita revisar -- no encaja con la explicación esperada.

with legacy as (
    select
        cm.cliente_id_limpio,
        case
            when cm.cliente_id_limpio like '800%'
                or cm.cliente_id_limpio like '801%'
                or cm.cliente_id_limpio like '802%'
                or len(cm.cliente_id_limpio) >= 10
            then 'Juridico'
            else 'Fisico'
        end as tipo_persona_legacy
    from {{ source('dato_solutions', 'clientes_mapeo') }} cm
),

nuevo as (
    select cliente_id_limpio, tipo_persona as tipo_persona_nuevo
    from {{ ref('int_clientes_limpio') }}
),

comparacion as (
    select
        coalesce(l.cliente_id_limpio, n.cliente_id_limpio) as cliente_id_limpio,
        l.tipo_persona_legacy,
        n.tipo_persona_nuevo
    from legacy l
    full outer join nuevo n
        on l.cliente_id_limpio = n.cliente_id_limpio
)

-- 1) Resumen de diferencias
select
    tipo_persona_legacy,
    tipo_persona_nuevo,
    count(*) as cantidad
from comparacion
where tipo_persona_legacy is not null and tipo_persona_nuevo is not null
group by tipo_persona_legacy, tipo_persona_nuevo

-- 2) Para inspeccionar los casos donde difieren -- comentar el select
--    de arriba y descomentar este. Todo lo que aparezca acá con
--    cliente_id_limpio que NO arranca en 803-899 (LEFT(cliente_id_limpio,3)
--    fuera de ese rango) es lo que hay que revisar en detalle.
--
-- select cliente_id_limpio, tipo_persona_legacy, tipo_persona_nuevo
-- from comparacion
-- where tipo_persona_legacy <> tipo_persona_nuevo
-- order by cliente_id_limpio;
