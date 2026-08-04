-- 1:1 sobre dbo.Clientes (tabla cruda, no el mapeo ya limpiado). Insumo
-- de int_clientes_mapeo_limpio (Fase 2) -- la limpieza de ID/nombre
-- (equivalente KNIME: mayúsculas, remoción de acentos/espacios/'|'/letras,
-- colapso por '-'/'*') vive ahí, no en este modelo.
select
    cast(cliente_id as varchar(255)) as cliente_id,
    cast(ci_ruc     as varchar(255)) as ci_ruc,
    cast(nombre     as varchar(255)) as nombre,
    cast(celular    as varchar(50))  as celular,
    cast(mail       as varchar(255)) as mail
from {{ source('dato_solutions', 'Clientes') }}
where cliente_id is not null
