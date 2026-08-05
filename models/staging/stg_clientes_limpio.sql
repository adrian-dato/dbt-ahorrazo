-- Fase 2 VALIDADA (ver PENDIENTES.md): repuntado de
-- source('dato_solutions','clientes_limpio') (proceso legacy) a
-- ref('int_clientes_limpio').
select
    cliente_id_limpio,
    nombre
from {{ ref('int_clientes_limpio') }}
