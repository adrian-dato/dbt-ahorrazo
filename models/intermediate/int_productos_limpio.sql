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
-- categoria_4_limpio='Mochila'. Confirmado con el usuario -- el
-- fallback es a categoria_3, no un default genérico. Se conserva
-- categoria_4 sin tocar al lado, para poder auditar cuántas filas se
-- completaron así.
--
-- table, no view: este modelo se une contra stg_ventas (238M+ filas)
-- dentro de int_ventas_elegibles, que alimenta los 3 proyectos -- como
-- view, el filtro de categoría + el LEFT JOIN a productos_excluidos se
-- recalcularía contra la fact completa en cada corrida. Mismo criterio
-- que int_clientes_limpio (dimensión chica, reusada contra una fact
-- grande -- ver el comentario de `intermediate:` en dbt_project.yml).

{{ config(materialized='table') }}

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
