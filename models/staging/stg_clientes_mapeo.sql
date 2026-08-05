-- Normaliza el tipo de cliente_id una sola vez acá (antes era un CTE
-- repetido en cada corrida de proc_1_36m.sql, para evitar que el
-- optimizador invirtiera la conversión implícita en el JOIN contra
-- Ventas_Ahorrazo.cliente_id).
--
-- Fase 2 VALIDADA (ver PENDIENTES.md): repuntado de
-- source('dato_solutions','clientes_mapeo') (proceso legacy,
-- clientes_mapeo_limpio.sql, sin correr hace meses -- confirmado con el
-- usuario) a ref('int_clientes_mapeo_limpio'). conteo_solo_nuevo=0 (sin
-- contar los ~5985 clientes nuevos acumulados por el atraso del legacy,
-- que es exactamente el problema que esta migración resuelve).
select
    cast(cliente_id        as varchar(50)) as cliente_id,
    cast(cliente_id_limpio as varchar(50)) as cliente_id_limpio
from {{ ref('int_clientes_mapeo_limpio') }}
