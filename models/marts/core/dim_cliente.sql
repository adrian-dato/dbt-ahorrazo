-- La dimensión de clientes: una fila por cliente_id_limpio, con su identidad y
-- las etiquetas que les ponen los análisis. Es la tabla que se une para ver
-- quién es un cliente y en qué segmento quedó.
--
-- EL LUGAR EN LA CADENA. Está al final y no al principio. Reúne resultados de
-- los análisis (hoy, la clasificación de Mayoristas), así que depende de ellos,
-- y los análisis no pueden leerla: si Mayoristas leyera dim_cliente y dim_cliente
-- leyera a Mayoristas, dbt no podría ordenarlos y fallaría por dependencia
-- circular. Los análisis leen la identidad de int_clientes_limpio, el insumo, y
-- cada uno saca de su propio resultado lo que necesita de los demás: la
-- segmentación RFM, por ejemplo, toma segmento_mayorista de
-- mayoristas_v3_resumen, que es donde se define.
--
-- QUIÉNES ESTÁN. Todos los cliente_id_limpio del mapeo de clientes, no solo los
-- que tienen ficha en dbo.Clientes. Los clientes que compran pero nunca se dieron
-- de alta no figuran en int_clientes_limpio, y sin ellos la dimensión dejaría
-- ventas sin cliente. Salen con nombre '(sin ficha)' y tiene_ficha en 0; su
-- tipo_persona se calcula igual, porque solo depende del número de documento.
--
-- LAS ETIQUETAS. Vienen de la clasificación de Mayoristas, que mira los últimos
-- 12 meses cerrados: un cliente sin compras en esa ventana no tiene fila ahí y
-- sale como 'Sin clasificar'. Es la etiqueta vigente. La historia de cómo
-- cambió cada cliente de nivel está en el snapshot de Mayoristas
-- (snapshots.mayoristas_v3_resumen_snapshot).
--
-- SIN DATOS DE CONTACTO. Celular y mail son datos personales y esta dimensión
-- la lee cualquier análisis. Quien los necesite, como la ficha del tablero de
-- Mayoristas, los toma de int_clientes_limpio.
--
-- Las etiquetas de otros análisis (la segmentación RFM, el tipo de
-- Canibalización) se suman acá cuando esos análisis estén construidos.
--
-- Las columnas de texto usan coalesce y no isnull: isnull devuelve el tipo del
-- primer argumento, y 'Sin clasificar' (14 caracteres) quedaría cortado a la
-- longitud de 'Potencial' (9).

{{ config(materialized='table') }}

with universo as (
    select distinct cliente_id_limpio
    from {{ ref('int_clientes_mapeo_limpio') }}
)

select
    u.cliente_id_limpio,
    coalesce(c.nombre, '(sin ficha)')                     as nombre,
    c.ci_ruc                                              as documento,
    {{ clasificar_tipo_persona('u.cliente_id_limpio') }}  as tipo_persona,
    case when c.cliente_id_limpio is null then 0 else 1 end as tiene_ficha,
    coalesce(m.nivel_mayorista, 'Sin clasificar')          as nivel_mayorista,
    coalesce(m.segmento_mayorista, 'Sin clasificar')       as segmento_mayorista,
    coalesce(f.frecuencia_compra, 'Sin clasificar')        as frecuencia_compra
from universo u
left join {{ ref('int_clientes_limpio') }} c
    on u.cliente_id_limpio = c.cliente_id_limpio
left join {{ ref('mayoristas_v3_resumen') }} m
    on u.cliente_id_limpio = m.cliente_id_limpio
left join {{ ref('mayoristas_v3_frecuencia_compra') }} f
    on u.cliente_id_limpio = f.cliente_id_limpio
