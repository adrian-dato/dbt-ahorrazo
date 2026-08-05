-- Única fuente de verdad para "qué es una venta válida para análisis"
-- (hallazgo del plan maestro: esta regla estaba duplicada e inconsistente
-- en 3 lugares -- proc_1_ventas_36m_agrupado.sql, la vista RFM
-- (ventas_filtradas_12m_usar_este_rfm_clustering.sql), y una lista
-- hardcodeada aparte en top_300_productos.ipynb, celda con
-- `excluir_producto_id = [...]`, que no existía en ningún script SQL).
--
-- Reglas unificadas:
--   - Solo empresa 3.
--   - Excluye categoría 2 "bolsa", categoría 1 "egre"/"servi".
--   - Excluye el cliente de test histórico (44444401).
--   - Excluye la lista de producto_id de seeds/productos_excluidos.csv
--     (antes solo aplicaba a Top 300 -- ahora es pareja para los 3).
--
-- View, sin materializar: cada mart consumidor define su propia ventana
-- de fechas sobre este resultado, acá no se fija ninguna.
--
-- IMPORTANTE: usa stg_clientes_mapeo (fuente legacy todavía), NO
-- int_clientes_mapeo_limpio -- ese cambio se hace recién cuando la
-- Fase 2 esté validada (ver PENDIENTES.md, no usar antes de eso).
--
-- fct_ventas_36m (Canibalización) TODAVÍA no consume este modelo --
-- sigue con su propia copia inline de estas mismas reglas, ya construida
-- y testeada. Migrarlo a ref(this) es limpieza pendiente (ver
-- PENDIENTES.md), no bloqueante: los marts nuevos (Top 300, Mayoristas)
-- sí arrancan usando este modelo desde el principio.

select
    v.cliente_id,
    c.cliente_id_limpio,
    v.producto_id,
    v.pdv_id,
    v.fecha_venta,
    v.venta_gs
from {{ ref('stg_ventas') }} v
inner join {{ ref('stg_clientes_mapeo') }} c
    on v.cliente_id = c.cliente_id
inner join {{ ref('stg_productos') }} p
    on v.producto_id = p.producto_id
left join {{ ref('productos_excluidos') }} pe
    on v.producto_id = pe.producto_id
where
    isnull(c.cliente_id_limpio, '') <> '44444401'
    and p.id_empresa = 3
    and isnull(p.categoria_2, '') not like '%bolsa%'
    and isnull(p.categoria_1, '') not like '%egre%'
    and isnull(p.categoria_1, '') not like '%servi%'
    and pe.producto_id is null
