-- Normaliza el tipo de cliente_id una sola vez acá (antes era un CTE
-- repetido en cada corrida de proc_1_36m.sql, para evitar que el
-- optimizador invirtiera la conversión implícita en el JOIN contra
-- Ventas_Ahorrazo.cliente_id).
--
-- Fuente hoy: la tabla dbo.clientes_mapeo generada por el proceso legacy
-- (scripts-sql-ahorrazo/prod/clientes_mapeo_limpio.sql). Se reemplaza por
-- ref('int_clientes_mapeo_limpio') una vez validada la Fase 2 — este
-- modelo no cambia de forma en ese momento, solo cambia lo que hay
-- "debajo" del source.
select
    cast(cliente_id        as varchar(50)) as cliente_id,
    cast(cliente_id_limpio as varchar(50)) as cliente_id_limpio
from {{ source('dato_solutions', 'clientes_mapeo') }}
