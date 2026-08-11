-- SCD2 sobre dim_clientes_mayoristas. A diferencia de
-- dim_cliente_tipo_migracion, este modelo NO tiene dimensión de tiempo
-- -- grano (ambito, cliente_id_limpio), un solo estado actual por
-- cliente. Sin esto, es imposible responder "¿cuándo pasó este cliente a
-- Alto?" -- cada rebuild pisa el nivel anterior sin dejar rastro.
--
-- check_cols=['nivel_mayorista', 'puntaje']: a propósito NO se incluyen
-- las métricas continuas (umbral_upt, umbral_pct, ventas_totales, etc.)
-- -- esas fluctúan de corrida en corrida aunque la clasificación de
-- negocio no cambie (ej. el Q3 del ámbito se corre un poco al agregarse
-- un mes más de datos). Versionar por cada micro-fluctuación de un
-- percentil generaría ruido, no historia útil. Se versiona solo cuando
-- cambia lo que realmente le importa al negocio: el nivel y el puntaje
-- que lo sostiene.
--
-- invalidate_hard_deletes=True (a diferencia del snapshot de
-- Canibalización): acá si un cliente desaparece de
-- dim_clientes_mayoristas SÍ es una señal real -- dejó de tener
-- actividad en la ventana de 12 meses que alimenta
-- int_mayoristas_metricas_cliente, es decir, dejó de calificar para
-- cualquier nivel. Se cierra la versión (dbt_valid_to) en vez de dejarla
-- open para siempre como si siguiera vigente.
--
-- strategy='check', no 'timestamp': es una tabla derivada, sin
-- updated_at real de origen.
--
-- Primer uso de snapshots en este proyecto -- ver nota de riesgo del
-- adaptador comunitario en dim_cliente_tipo_migracion_snapshot.sql /
-- PENDIENTES.md.

{% snapshot dim_clientes_mayoristas_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='ambito_cliente_key',
        strategy='check',
        check_cols=['nivel_mayorista', 'puntaje'],
        invalidate_hard_deletes=True,
    )
}}

select
    concat(ambito, '-', cliente_id_limpio) as ambito_cliente_key,
    ambito,
    cliente_id_limpio,
    nivel_mayorista,
    puntaje
from {{ ref('dim_clientes_mayoristas') }}

{% endsnapshot %}
