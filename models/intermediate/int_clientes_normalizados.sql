-- Limpieza de clientes (equivalente KNIME), calculada UNA sola vez acá.
-- El proceso legacy (clientes_mapeo_limpio.sql) recomputa esta misma
-- limpieza dos veces por separado: una vez para construir clientes_mapeo
-- (paso A) y otra para construir clientes_limpio (paso D). Acá se hace
-- una sola vez y los dos modelos que la necesitan (int_clientes_mapeo_limpio,
-- int_clientes_limpio) reutilizan este resultado.
--
-- nombre_limpio sigue llamando a dbo.fn_nombre_limpio() (función ya
-- existente en la base, creada por el proceso legacy) en vez de
-- reimplementarse acá: esa función colapsa espacios múltiples con un
-- WHILE loop iterativo que no se puede expresar de forma exacta como una
-- sola expresión SQL sin aproximar -- y aproximar es justo el tipo de
-- diferencia sutil que este campo (el más "verboso" de la limpieza) no
-- puede permitirse. No decomisionar esta función al apagar el resto del
-- stored proc legacy.
--
-- cliente_id_limpio puede salir NULL: pasa cuando el cliente_id original
-- no tenía ningún dígito (ej. quedó cargado un nombre de persona en vez
-- de un documento -- "ABRAHAM", "SIN NOMBRE"). Son clientes no
-- identificables -- decisión de negocio es excluirlos de la
-- segmentación, no inventarles un id (ver derivar_cliente_id_limpio).
-- int_clientes_limpio ya filtra esto; int_clientes_mapeo_limpio también.

with normalizado as (
    select
        cliente_id,
        ci_ruc,
        celular,
        mail,
        dbo.fn_nombre_limpio(nombre)                                       as nombre_limpio,
        {{ recortar_basura_extremos(limpiar_id('cliente_id')) }}          as cliente_id_clean,
        {{ limpiar_id("isnull(ci_ruc, N'')") }}                            as ci_ruc_clean
    from {{ ref('stg_clientes') }}
)

select
    cliente_id,
    cliente_id_clean,
    {{ derivar_cliente_id_limpio('cliente_id_clean') }} as cliente_id_limpio,
    ci_ruc_clean,
    nombre_limpio,
    celular,
    mail
from normalizado
