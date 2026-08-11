-- SCD2 sobre dim_cliente_tipo_migracion. El modelo YA tiene grano
-- (cliente_id_limpio, anio, mes) -- esto no le agrega "historia" nueva,
-- agrega algo distinto: preservar qué `tipo_cliente` se reportó para un
-- (cliente, mes) puntual en cada corrida, aunque una corrida futura lo
-- recalcule distinto.
--
-- Por qué puede recalcularse distinto: tipo_cliente sale de un acumulado
-- corrido (SUM() OVER ... ROWS UNBOUNDED PRECEDING, ver el modelo). Si
-- llega una venta tarde para un mes ya cerrado (el lookback de
-- fct_ventas_36m lo contempla a propósito), el acumulado de ESE mes en
-- adelante cambia para TODOS los meses posteriores del cliente -- y como
-- el modelo es materialized='table' (full rebuild), la próxima corrida
-- reescribe en silencio una clasificación que ya se había reportado.
-- Sin este snapshot, no queda rastro de qué se dijo en su momento.
--
-- strategy='check' (no 'timestamp'): no hay un updated_at real, es una
-- tabla derivada, no una fuente con fecha de modificación.
--
-- invalidate_hard_deletes=False (default, explícito acá): un
-- (cliente, mes) puede desaparecer de dim_cliente_tipo_migracion sin que
-- pase nada raro -- fct_ventas_36m es una ventana rolling de 36 meses,
-- así que meses viejos caen del rango con el tiempo. Eso NO es un evento
-- de negocio ("dejó de ser cliente"), es solo que la fuente rolling ya
-- no lo cubre -- el snapshot debe seguir mostrando ese último valor
-- conocido como válido, no cerrarlo.
--
-- Primera corrida: inserta todo el estado actual como versión 1
-- (dbt_valid_from = ahora, dbt_valid_to = NULL). La "historia" empieza a
-- verse recién desde la SEGUNDA corrida en que algo cambie.
--
-- Primer uso de snapshots en este proyecto -- no probado todavía contra
-- dbt-sqlserver (adaptador comunitario, mismo riesgo ya conocido que con
-- contracts). Ver PENDIENTES.md.

{% snapshot dim_cliente_tipo_migracion_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='cliente_mes_key',
        strategy='check',
        check_cols=['tipo_cliente'],
        invalidate_hard_deletes=False,
    )
}}

select
    concat(cliente_id_limpio, '-', cast(anio as varchar(4)), '-', cast(mes as varchar(2))) as cliente_mes_key,
    cliente_id_limpio,
    anio,
    mes,
    tipo_cliente
from {{ ref('dim_cliente_tipo_migracion') }}

{% endsnapshot %}
