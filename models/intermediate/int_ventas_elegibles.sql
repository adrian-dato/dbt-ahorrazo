-- Única fuente de verdad para "qué es una venta válida para análisis"
-- (hallazgo del plan maestro: esta regla estaba duplicada e inconsistente
-- en 3 lugares -- proc_1_ventas_36m_agrupado.sql, la vista RFM
-- (ventas_filtradas_12m_usar_este_rfm_clustering.sql), y una lista
-- hardcodeada aparte en top_300_productos.ipynb, celda con
-- `excluir_producto_id = [...]`, que no existía en ningún script SQL).
--
-- Reglas unificadas:
--   - Del lado del producto (empresa, categoría_1/2, producto_excluido):
--     vive en int_productos_limpio, no acá -- este modelo hace INNER JOIN
--     ahí en vez de repetir el WHERE. Ver ese modelo para el detalle
--     completo de qué se excluye y por qué.
--   - Del lado de la venta/cliente: excluye el cliente de test histórico
--     (44444401) -- esto sí queda acá, es una propiedad de la venta, no
--     del producto.
--
-- View, sin materializar: cada mart consumidor define su propia ventana
-- de fechas sobre este resultado, acá no se fija ninguna.
--
-- IMPORTANTE: usa stg_clientes_mapeo (fuente legacy todavía), NO
-- int_clientes_mapeo_limpio -- ese cambio se hace recién cuando la
-- Fase 2 esté validada (ver PENDIENTES.md, no usar antes de eso).
--
-- fct_ventas_36m (Canibalización) ya consume este modelo (migrado --
-- antes tenía su propia copia inline de estas mismas reglas). Efecto de
-- la migración: ahora también aplica la exclusión de
-- productos_excluidos, que antes solo corría para Top 300.
--
-- cast(producto_id as varchar(100)) explícito en el JOIN de acá abajo:
-- mismo motivo que en top300_ranking.sql -- no alcanza con que
-- stg_ventas/int_productos_limpio ya casteen, si la tabla física del
-- otro lado del JOIN queda con un tipo distinto (ej. un seed creado
-- antes de que existiera su `column_types`, que solo se aplica al crear
-- la tabla, no en un TRUNCATE+INSERT sobre una que ya existe) SQL Server
-- intenta convertir ESTE lado a ese tipo por precedencia, y explota con
-- cualquier producto_id no numérico o fuera de rango de int.

select
    v.cliente_id,
    c.cliente_id_limpio,
    v.producto_id,
    v.pdv_id,
    v.fecha_venta,
    v.venta_gs,
    v.unidades,
    -- ticket_id: mismo criterio que view_ventas_ahorrazo_filtradas_12m y
    -- top_300_productos.ipynb (ahí "ticked_id", typo heredado -- acá
    -- corregido a ticket_id, mismo criterio de construcción).
    concat(cast(v.timbrado as varchar(50)), '_', cast(v.factura_nro as varchar(50))) as ticket_id,
    -- Directo acá (no vía join a int_clientes_limpio) a propósito: es
    -- solo una función del string cliente_id_limpio, no depende de
    -- dbo.Clientes -- así cubre también a los clientes "huérfanos" (ven
    -- en Ventas pero no en Clientes) que int_clientes_limpio no tiene.
    -- Misma macro que usa int_clientes_limpio -- 1 sola definición de la
    -- regla, materializada en los 2 lugares donde hace falta.
    {{ clasificar_tipo_persona('c.cliente_id_limpio') }} as tipo_persona
from {{ ref('stg_ventas') }} v
inner join {{ ref('stg_clientes_mapeo') }} c
    on v.cliente_id = c.cliente_id
inner join {{ ref('int_productos_limpio') }} p
    on cast(v.producto_id as varchar(100)) = cast(p.producto_id as varchar(100))
where
    isnull(c.cliente_id_limpio, '') <> '44444401'
