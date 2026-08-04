-- Test de sanidad sobre int_clientes_mapeo_limpio: si un mismo
-- cliente_id_limpio agrupa una cantidad anormal de cliente_id de origen
-- distintos, probablemente la heurística de colapso ("todo antes de '-'
-- o '*'") está fusionando clientes que no deberían fusionarse -- señal
-- de una regresión en la limpieza (ej. muchos ids que colapsan a
-- cadena vacía y caen todos en el mismo fallback), no de un negocio con
-- decenas de RUC/CI distintos bajo un mismo id_limpio.
--
-- Un dbt test "falla" si esta query devuelve filas -- el umbral (20) es
-- un punto de partida conservador, a ajustar una vez perfilada la
-- distribución real de ids-por-cliente en la base.

select
    cliente_id_limpio,
    count(distinct cliente_id) as cantidad_ids_origen
from {{ ref('int_clientes_mapeo_limpio') }}
group by cliente_id_limpio
having count(distinct cliente_id) > 20
