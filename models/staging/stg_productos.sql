-- Normaliza la collation de las columnas de categoría una sola vez acá
-- (antes se aplicaba COLLATE Latin1_General_CI_AI en cada corrida de
-- proc_1_36m.sql, en cada condición del WHERE).
select
    producto_id,
    id_empresa,
    categoria_1 collate Latin1_General_CI_AI as categoria_1,
    categoria_2 collate Latin1_General_CI_AI as categoria_2
from {{ source('dato_solutions', 'productos') }}
