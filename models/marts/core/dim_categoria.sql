-- Las categorías de producto con un código único por categoría. Una fila
-- por categoría de cada uno de los cuatro niveles (categoria_1 a
-- categoria_4), con su clave, la clave de su padre y su ruta legible.
--
-- POR QUÉ EXISTE. El nombre de una categoría no la identifica: 'Dama' está
-- bajo 81 categoria_3 distintas, y 8 nombres de categoria_2, 99 de
-- categoria_3 y 324 de categoria_4 se repiten bajo más de un padre. Agrupar
-- por nombre junta cosas distintas. Acá cada categoría se identifica por la
-- ruta completa desde la raíz, así que dos 'Dama' bajo padres distintos
-- tienen claves distintas.
--
-- ÁRBOL COMPLETO. Todo producto tiene una clave en los cuatro niveles; un
-- nivel sin valor (el comodín 'sin asignar.' afecta a 59.028 productos en
-- categoria_4) es un nodo '(sin asignar)' bajo su padre. Así todas las
-- hojas están a la misma profundidad y se puede sumar de abajo hacia
-- arriba sin casos especiales, que es lo que pide el forecast jerárquico.
-- Cada padre tiene su propio '(sin asignar)': el de una categoría no se
-- mezcla con el de otra.
--
-- La clave se arma en macros/clave_categoria.sql y el texto se normaliza en
-- macros/normalizar_categoria.sql. int_productos_limpio trae la clave de
-- cada nivel en cada producto: se une por ahí, no por nombre.
--
-- Vive en marts_core y no en intermediate porque es una tabla que leen los
-- consumidores (Power BI, forecasting, otros análisis) para ver los nombres
-- de las claves; intermediate es para lo que se construye y se usa adentro
-- de dbt.
--
-- La unicidad de categoria_key la prueba el schema.yml. Una colisión del
-- hash dejaría dos filas con la misma clave, porque acá se agrupa por clave
-- y por ruta normalizada a la vez, y ese test fallaría.

{{ config(materialized='table') }}

with partes as (
    select
        {{ normalizar_categoria('categoria_1') }} as n1,
        {{ normalizar_categoria('categoria_2') }} as n2,
        {{ normalizar_categoria('categoria_3') }} as n3,
        {{ normalizar_categoria('categoria_4') }} as n4,
        {{ nombre_categoria('categoria_1') }}     as nombre_1,
        {{ nombre_categoria('categoria_2') }}     as nombre_2,
        {{ nombre_categoria('categoria_3') }}     as nombre_3,
        {{ nombre_categoria('categoria_4') }}     as nombre_4
    from {{ ref('int_productos_limpio') }}
),

claves as (
    select
        *,
        {{ clave_categoria(1, ['n1']) }}                      as key_n1,
        {{ clave_categoria(2, ['n1', 'n2']) }}                as key_n2,
        {{ clave_categoria(3, ['n1', 'n2', 'n3']) }}          as key_n3,
        {{ clave_categoria(4, ['n1', 'n2', 'n3', 'n4']) }}    as key_n4
    from partes
)

select
    1                                       as nivel,
    key_n1                                  as categoria_key,
    cast(null as varchar(15))               as categoria_padre_key,
    n1                                      as ruta_normalizada,
    max(nombre_1)                           as nombre,
    max(nombre_1)                           as ruta,
    count(*)                                as cant_productos
from claves
group by key_n1, n1

union all

select
    2,
    key_n2,
    key_n1,
    concat_ws(N'|', n1, n2),
    max(nombre_2),
    concat_ws(N' > ', max(nombre_1), max(nombre_2)),
    count(*)
from claves
group by key_n2, key_n1, n1, n2

union all

select
    3,
    key_n3,
    key_n2,
    concat_ws(N'|', n1, n2, n3),
    max(nombre_3),
    concat_ws(N' > ', max(nombre_1), max(nombre_2), max(nombre_3)),
    count(*)
from claves
group by key_n3, key_n2, n1, n2, n3

union all

select
    4,
    key_n4,
    key_n3,
    concat_ws(N'|', n1, n2, n3, n4),
    max(nombre_4),
    concat_ws(N' > ', max(nombre_1), max(nombre_2), max(nombre_3), max(nombre_4)),
    count(*)
from claves
group by key_n4, key_n3, n1, n2, n3, n4
