-- Fuente hoy: dbo.clientes_limpio generada por el proceso legacy
-- (clientes_mapeo_limpio.sql). Se reemplaza por
-- ref('int_clientes_mapeo_limpio') en la Fase 2.
select
    cliente_id_limpio,
    nombre
from {{ source('dato_solutions', 'clientes_limpio') }}
