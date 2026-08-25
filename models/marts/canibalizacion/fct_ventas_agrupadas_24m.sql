-- Reemplaza scripts-sql-ahorrazo/prod/ventas_agrupadas_24m.sql
-- (dbo.ventas_ahorrazo_agrupadas_24m) -- tabla fuente de un .pbix de
-- Canibalización de Sucursales que nunca se orquestó (nada la volvía a
-- correr). Grano: mes x cliente_id_limpio x pdv_id x categoria_1-4 x
-- marca x tipo_persona -- igual al legacy, salvo 3 decisiones tomadas
-- a propósito distinto, confirmadas con el usuario (ver
-- CONTEXTO_SESION.md sección 9):
--
--   1. Ventana de fct_ventas_agrupadas_ventana_meses (24) meses ANCLADA
--      AL MÁXIMO PERÍODO PRESENTE EN LOS DATOS, no a GETDATE() como el
--      legacy -- mismo criterio que int_canibalizacion_migracion_base
--      (canibalizacion_v3_ventana_meses), vía el mismo macro
--      meses_entre_periodos().
--   2. Filtro de producto vía int_productos_limpio -- excluye también
--      categoria_1 Activo/Insumos y productos_excluidos, que el script
--      legacy no excluía.
--   3. tipo_persona vía la macro clasificar_tipo_persona (ya resuelta
--      en int_ventas_elegibles, aplicada sobre cliente_id_limpio), no
--      la heurística vieja del script (LIKE '800%'/'801%'/'802%' OR
--      LEN>=10).
--
-- 2 diferencias más, heredadas de la arquitectura actual, no de una
-- decisión nueva de este modelo:
--   - Solo cliente_id_limpio, sin la columna cliente_id cruda que traía
--     el legacy -- cliente_id_limpio ya es la identidad de cliente
--     correcta en todo el proyecto; repetir el grano por cliente_id
--     crudo reintroduciría la fragmentación que la limpieza de
--     clientes existe para resolver.
--   - int_ventas_elegibles hace INNER JOIN a stg_clientes_mapeo (no
--     LEFT como el legacy a dbo.clientes_mapeo) -- una venta cuyo
--     cliente_id no tiene match ahí se descarta en vez de pasar con
--     cliente_id_limpio NULL. No se replicó el filtro adicional
--     LEN(cliente_id_limpio) > 4 del legacy tampoco -- la limpieza de
--     clientes actual ya maneja ids no identificables poniendo
--     cliente_id_limpio en NULL (ver PENDIENTES.md, "Bugs encontrados"
--     punto 2), es el mecanismo equivalente con un criterio más
--     principista que un umbral de longitud arbitrario.

{{ config(materialized='table') }}

with ventas as (
    select
        *,
        year(fecha_venta) * 100 + month(fecha_venta) as periodo
    from {{ ref('int_ventas_elegibles') }}
),

periodo_max as (
    select max(periodo) as periodo_max from ventas
),

en_ventana as (
    select v.*
    from ventas v
    cross join periodo_max pm
    where {{ meses_entre_periodos('pm.periodo_max', 'v.periodo') }}
          <= {{ var('fct_ventas_agrupadas_ventana_meses') - 1 }}
)

select
    datefromparts(v.periodo / 100, v.periodo % 100, 1) as periodo,
    v.cliente_id_limpio,
    cl.nombre                                           as nombre_cliente,
    v.tipo_persona,
    v.pdv_id,
    p.categoria_1,
    p.categoria_2,
    p.categoria_3,
    p.categoria_4,
    p.marca,
    sum(v.unidades)                                     as unidades,
    sum(v.venta_gs)                                     as venta_gs,
    count(distinct v.ticket_id)                         as cant_tickets
from en_ventana v
inner join {{ ref('int_productos_limpio') }} p
    on cast(v.producto_id as varchar(100)) = cast(p.producto_id as varchar(100))
left join {{ ref('int_clientes_limpio') }} cl
    on v.cliente_id_limpio = cl.cliente_id_limpio
group by
    v.periodo,
    v.cliente_id_limpio,
    cl.nombre,
    v.tipo_persona,
    v.pdv_id,
    p.categoria_1,
    p.categoria_2,
    p.categoria_3,
    p.categoria_4,
    p.marca
