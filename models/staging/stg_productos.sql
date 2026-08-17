-- Normaliza la collation de las columnas de categoría una sola vez acá
-- (antes se aplicaba COLLATE Latin1_General_CI_AI en cada corrida de
-- proc_1_36m.sql, en cada condición del WHERE) -- solo categoria_1/2,
-- que son las que se usan en filtros de exclusión (int_ventas_elegibles);
-- categoria_3/4/5 no participan de ningún filtro hoy, se exponen tal cual.
--
-- producto_id casteado a varchar: mismo motivo que en stg_ventas (no es
-- puramente numérico en la base real -- ver ese archivo para el detalle).
--
-- nonbre -> nombre: la columna viene mal escrita en dbo.Productos
-- (confirmado contra INFORMATION_SCHEMA, no es un error de transcripción
-- acá) -- se corrige una sola vez acá en vez de que cada tablero/consumidor
-- downstream tenga que acordarse del typo del origen.
select
    cast(producto_id as varchar(100)) as producto_id,
    id_empresa,
    categoria_1 collate Latin1_General_CI_AI as categoria_1,
    categoria_2 collate Latin1_General_CI_AI as categoria_2,
    categoria_3,
    categoria_4,
    categoria_5,
    nonbre as nombre,
    marca,
    unidad_medida
from {{ source('dato_solutions', 'productos') }}
