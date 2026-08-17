-- Segunda hipótesis para el crecimiento sin explicar de 'Nuevo - Dual'
-- (ver PENDIENTES.md de canibalizacion_ahorrazo -- la primera hipótesis,
-- dedup multi-cliente_id, se verificó en verificar_hipotesis_nuevo_dual.sql
-- y explica solo ~18-35% del crecimiento).
--
-- stg_clientes_mapeo.sql documenta que el dedup de Fase 2
-- (int_clientes_mapeo_limpio) incorpora ~5.985 clientes "huérfanos"
-- (cliente_id que aparecen en Ventas_Ahorrazo pero NUNCA existieron en
-- dbo.Clientes -- el mapeo legacy, fuente de los números de referencia,
-- está parado hace meses y nunca los vio). Estos clientes no existen EN
-- ABSOLUTO en la referencia -- si su distribución de tipo_cliente está
-- sesgada hacia Dual (o cualquier categoría) respecto al resto de la
-- base, eso explicaría desviación adicional que no tiene nada que ver
-- con reclasificación de clientes existentes.
--
-- No es un modelo: compilar con
-- `dbt compile --select verificar_hipotesis_huerfanos_dual` y correr el
-- SQL resultante a mano, o `dbt show --select verificar_hipotesis_huerfanos_dual`.
--
-- Un cliente_id_limpio cuenta como "huérfano" acá solo si TODOS sus
-- cliente_id crudos son huérfanos (si tiene aunque sea 1 crudo que sí
-- existía en dbo.Clientes, ese cliente ya existía de alguna forma en el
-- mundo legacy, no es un caso "nuevo por completo").

with huerfanos as (
    select m.cliente_id
    from {{ ref('int_clientes_mapeo_limpio') }} m
    left join {{ ref('int_clientes_normalizados') }} n
        on m.cliente_id = n.cliente_id
    where n.cliente_id is null
),

cliente_limpio_huerfano as (
    select
        m.cliente_id_limpio,
        count(*)             as total_crudos,
        count(h.cliente_id)  as crudos_huerfanos
    from {{ ref('int_clientes_mapeo_limpio') }} m
    left join huerfanos h
        on m.cliente_id = h.cliente_id
    group by m.cliente_id_limpio
    having count(*) = count(h.cliente_id)
),

eventos as (
    select
        e.tipo_cliente,
        case when clh.cliente_id_limpio is not null then 1 else 0 end as es_huerfano
    from {{ ref('dim_cliente_migracion_eventos') }} e
    left join cliente_limpio_huerfano clh
        on e.cliente_id_limpio = clh.cliente_id_limpio
)

-- Resumen por tipo_cliente: ¿la tasa de huérfanos en 'Nuevo - Dual' es
-- más alta que en las otras 3 categorías (control)?
select
    tipo_cliente,
    count(*)                                          as total_eventos,
    sum(es_huerfano)                                   as huerfanos,
    cast(sum(es_huerfano) as float) / count(*)         as pct_huerfano
from eventos
where tipo_cliente in
    ('Nuevo - Dual', 'Nuevo - Unico', 'Recurrente - Dual', 'Recurrente - Migracion')
group by tipo_cliente
