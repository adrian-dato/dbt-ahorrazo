-- Reemplaza clientes_mapeo_limpio.sql, paso D: dimensión por
-- cliente_id_limpio (nombre/ci_ruc/celular/mail/tipo_persona).
--
-- table (no incremental): a diferencia del mapeo de arriba, esta
-- dimensión no depende de Ventas_pos -- sale entera de Clientes,
-- una tabla chica que no es la fuente del cuello de botella. Recalcularla
-- completa en cada corrida y dejar que dbt haga el swap atómico es más
-- simple que mantener un incremental acá, y evita el patrón
-- DROP+CREATE+sp_rename sin transacción visible del proceso anterior.
--
-- tipo_persona: ver macros/clasificar_tipo_persona.sql para el detalle
-- completo de la regla y por qué reemplaza al CASE hardcodeado de
-- view_ventas_ahorrazo_filtradas_12m, que ya está en desuso. Misma macro que
-- usa int_ventas_elegibles -- 1 sola definición de la regla, 2 lugares
-- donde conviene tener la columna materializada.

{{ config(materialized='table') }}

select
    cliente_id_limpio,
    max(nombre_limpio) as nombre,   -- mismo criterio que el proceso legacy (KNIME: Maximum)
    min(ci_ruc_clean)  as ci_ruc,   -- mismo criterio que el proceso legacy (determinístico)
    max(celular)       as celular,
    max(mail)          as mail,
    {{ clasificar_tipo_persona('cliente_id_limpio') }} as tipo_persona
from {{ ref('int_clientes_normalizados') }}
where cliente_id_limpio is not null
group by cliente_id_limpio
