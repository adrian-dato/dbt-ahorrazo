-- Reemplaza clientes_mapeo_limpio.sql, paso D: dimensión por
-- cliente_id_limpio (nombre/ci_ruc/celular/mail).
--
-- table (no incremental): a diferencia del mapeo de arriba, esta
-- dimensión no depende de Ventas_Ahorrazo -- sale entera de Clientes,
-- una tabla chica que no es la fuente del cuello de botella. Recalcularla
-- completa en cada corrida y dejar que dbt haga el swap atómico es más
-- simple que mantener un incremental acá, y sigue eliminando el patrón
-- DROP+CREATE+sp_rename sin transacción visible del proceso legacy.
--
-- Nota: todavía NO reemplaza a stg_clientes_limpio -- corre en paralelo
-- al proceso legacy hasta validar (ver analyses/validar_clientes_mapeo_limpio.sql).

{{ config(materialized='table') }}

select
    cliente_id_limpio,
    max(nombre_limpio) as nombre,   -- mismo criterio que el proceso legacy (KNIME: Maximum)
    min(ci_ruc_clean)  as ci_ruc,   -- mismo criterio que el proceso legacy (determinístico)
    max(celular)       as celular,
    max(mail)          as mail
from {{ ref('int_clientes_normalizados') }}
where cliente_id_limpio is not null
group by cliente_id_limpio
