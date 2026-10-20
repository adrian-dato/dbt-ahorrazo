-- Fuente única de "producto elegible para análisis" + categorías
-- limpias -- antes el filtro de empresa/categoría/producto_excluido
-- vivía inline en el WHERE de int_ventas_elegibles; se mueve acá para
-- que cualquier consumidor futuro que necesite "productos válidos" sin
-- pasar por ventas (o por otra fact futura) no tenga que repetirlo.
-- int_ventas_elegibles ahora hace INNER JOIN acá en vez de filtrar de
-- nuevo.
--
-- A diferencia de int_clientes_limpio (catálogo general de clientes,
-- SIN filtrar elegibilidad -- esa queda en int_ventas_elegibles porque
-- es una propiedad de la VENTA, no del cliente en sí, ej. el cliente de
-- test 44444401 sigue siendo un cliente real), acá sí tiene sentido
-- filtrar de una: "producto elegible" es una propiedad casi siempre fija
-- del producto (empresa/categoría), no depende de cada venta puntual.
--
-- categoria_4_limpio: cuando categoria_4 = 'sin asignar.' (placeholder
-- real de la fuente, no NULL), usa categoria_3 como fallback -- ej.
-- categoria_3='Mochila' + categoria_4='sin asignar.' ->
-- categoria_4_limpio='Mochila'. El fallback es a categoria_3, no un
-- default genérico. Se conserva
-- categoria_4 sin tocar al lado, para poder auditar cuántas filas se
-- completaron así.
--
-- categoria_4_limpio NO sirve como identificador de categoría: mezcla dos
-- niveles en la misma columna (los nombres de categoria_4 y, donde esa
-- falta, los de categoria_3), y los nombres se repiten bajo distintos
-- padres. Para agrupar por categoría se usan categoria_key_n1 a
-- categoria_key_n4, que identifican cada nivel por su ruta completa
-- (ver macros/clave_categoria.sql). Todo producto tiene una clave en los
-- cuatro niveles: un nivel sin valor es un nodo '(sin asignar)' bajo su
-- padre, no un hueco. La tabla de categorías es dim_categoria (marts_core).
--
-- table, no view: este modelo se une contra stg_ventas (238M+ filas)
-- dentro de int_ventas_elegibles, que alimenta los 3 proyectos -- como
-- view, el filtro de categoría + el LEFT JOIN a productos_excluidos se
-- recalcularía contra la fact completa en cada corrida. Mismo criterio
-- que int_clientes_limpio (dimensión chica, reusada contra una fact
-- grande -- ver el comentario de `intermediate:` en dbt_project.yml).

{{ config(materialized='table') }}

with base as (
    select
        p.producto_id,
        p.id_empresa,
        p.categoria_1,
        p.categoria_2,
        p.categoria_3,
        p.categoria_4,
        case
            when p.categoria_4 = 'sin asignar.' then p.categoria_3
            else p.categoria_4
        end as categoria_4_limpio,
        p.categoria_5,
        p.nombre,
        p.marca,
        p.unidad_medida
    from {{ ref('stg_productos') }} p
    left join {{ ref('productos_excluidos') }} pe
        on cast(p.producto_id as varchar(100)) = cast(pe.producto_id as varchar(100))
    where
        p.id_empresa = 3
        and isnull(p.categoria_2, '') not like '%bolsa%'
        and isnull(p.categoria_1, '') not like '%egre%'
        and isnull(p.categoria_1, '') not like '%servi%'
        and isnull(p.categoria_1, '') not like '%activo%'
        and isnull(p.categoria_1, '') not like '%insumos%'
        and pe.producto_id is null
),

normalizado as (
    select
        *,
        {{ normalizar_categoria('categoria_1') }} as n1,
        {{ normalizar_categoria('categoria_2') }} as n2,
        {{ normalizar_categoria('categoria_3') }} as n3,
        {{ normalizar_categoria('categoria_4') }} as n4
    from base
)

select
    producto_id,
    id_empresa,
    categoria_1,
    categoria_2,
    categoria_3,
    categoria_4,
    categoria_4_limpio,
    categoria_5,
    nombre,
    marca,
    unidad_medida,
    {{ clave_categoria(1, ['n1']) }}                      as categoria_key_n1,
    {{ clave_categoria(2, ['n1', 'n2']) }}                as categoria_key_n2,
    {{ clave_categoria(3, ['n1', 'n2', 'n3']) }}          as categoria_key_n3,
    {{ clave_categoria(4, ['n1', 'n2', 'n3', 'n4']) }}    as categoria_key_n4
from normalizado
