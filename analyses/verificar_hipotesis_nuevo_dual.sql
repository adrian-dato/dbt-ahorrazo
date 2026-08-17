-- Verifica la hipótesis abierta en PENDIENTES.md (canibalizacion_ahorrazo)
-- sobre el crecimiento de 'Nuevo - Dual' en dim_cliente_migracion_eventos
-- (11.210 -> 20.057 eventos, +78,9% vs. +2,8% del total de eventos):
-- que el dedup de cliente_id de Fase 2 (int_clientes_mapeo_limpio) esté
-- consolidando clientes que antes se veían como 2 cliente_id_limpio
-- separados (cada uno "nuevo en 1 sola sucursal") en 1 solo
-- cliente_id_limpio -- que cae en la categoría 'Nuevo - Dual' por
-- construcción (2 sucursales con primer_periodo_sucursal = primer mes
-- del cliente, ver el comentario de dim_cliente_migracion_eventos.sql).
--
-- No es un modelo: compilar con
-- `dbt compile --select verificar_hipotesis_nuevo_dual` y correr el SQL
-- resultante a mano, o `dbt show --select verificar_hipotesis_nuevo_dual`.
--
-- 3 secciones -- solo puede haber 1 SELECT final activo a la vez, para
-- pasar de una a otra comentar la activa y descomentar la siguiente
-- (mismo patrón que validar_clientes_mapeo_limpio.sql):
--
--   1) (activa por default) Resumen comparativo: ¿el % de eventos cuyo
--      cliente_id_limpio viene de 2+ cliente_id crudos es más alto en
--      'Nuevo - Dual' que en 'Nuevo - Unico' (control)? Si sí, apoya la
--      hipótesis; si el % es similar en las 2 categorías, la hipótesis
--      no alcanza a explicar la desviación y hay que buscar otra causa.
--   2) Confirmación mecánica, solo sobre los 'Nuevo - Dual' con dedup
--      multi-cliente_id: ¿cada cliente_id crudo (sin el dedup) vendió en
--      UNA sola de las 2 sucursales del evento, nunca las 2? Si la
--      hipótesis es correcta, casi todo debería caer en
--      sucursales_distintas = 1.
--   3) Muestra de 10 casos concretos (cliente_id_limpio + sus
--      cliente_id crudos) para inspección manual.

with mapeo_multi as (
    select
        cliente_id_limpio,
        count(distinct cliente_id) as cliente_ids_crudos
    from {{ ref('int_clientes_mapeo_limpio') }}
    group by cliente_id_limpio
),

eventos as (
    select
        e.cliente_id_limpio,
        e.tipo_cliente,
        e.local_origen,
        e.local_destino,
        e.anio,
        e.mes,
        coalesce(m.cliente_ids_crudos, 1) as cliente_ids_crudos
    from {{ ref('dim_cliente_migracion_eventos') }} e
    left join mapeo_multi m
        on e.cliente_id_limpio = m.cliente_id_limpio
),

candidatos as (
    -- 'Nuevo - Dual' cuyo cliente_id_limpio viene de 2+ cliente_id crudos.
    select cliente_id_limpio, local_origen, local_destino, anio, mes
    from eventos
    where tipo_cliente = 'Nuevo - Dual' and cliente_ids_crudos > 1
),

ventas_crudo as (
    -- Ventas de cada cliente_id crudo (SIN el dedup de Fase 2), por
    -- sucursal, acotadas al mes del evento y a las 2 sucursales del
    -- evento (local_origen/local_destino) -- para ver si cada
    -- cliente_id crudo tocó 1 sola o las 2.
    select
        v.cliente_id      as cliente_id_crudo,
        v.cliente_id_limpio,
        s.sucursal_codigo as sucursal
    from {{ ref('int_ventas_elegibles') }} v
    inner join {{ ref('dim_sucursal_mapeo') }} s
        on v.pdv_id = s.pdv_id
    inner join candidatos c
        on v.cliente_id_limpio = c.cliente_id_limpio
       and year(v.fecha_venta)  = c.anio
       and month(v.fecha_venta) = c.mes
       and s.sucursal_codigo in (c.local_origen, c.local_destino)
    group by v.cliente_id, v.cliente_id_limpio, s.sucursal_codigo
),

sucursales_por_crudo as (
    select
        cliente_id_limpio,
        cliente_id_crudo,
        count(distinct sucursal) as sucursales_distintas
    from ventas_crudo
    group by cliente_id_limpio, cliente_id_crudo
)

-- 1) Resumen comparativo
select
    tipo_cliente,
    count(*) as total_eventos,
    sum(case when cliente_ids_crudos > 1 then 1 else 0 end) as con_dedup_multi,
    cast(sum(case when cliente_ids_crudos > 1 then 1 else 0 end) as float)
        / count(*) as pct_con_dedup_multi
from eventos
where tipo_cliente in ('Nuevo - Dual', 'Nuevo - Unico')
group by tipo_cliente

-- 2) Confirmación mecánica -- comentar el select de arriba y
--    descomentar este:
--
-- select
--     sucursales_distintas,
--     count(*) as cantidad_cliente_id_crudos
-- from sucursales_por_crudo
-- group by sucursales_distintas;

-- 3) Muestra de 10 casos concretos -- comentar el select activo y
--    descomentar este:
--
-- select top 10
--     c.cliente_id_limpio, c.local_origen, c.local_destino, c.anio, c.mes,
--     v.cliente_id_crudo, v.sucursal
-- from candidatos c
-- inner join ventas_crudo v
--     on c.cliente_id_limpio = v.cliente_id_limpio
-- order by c.cliente_id_limpio, v.cliente_id_crudo;
