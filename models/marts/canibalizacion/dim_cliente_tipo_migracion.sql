-- Reemplaza _conditions() (canibalizacion_v1_usado.ipynb, celda "def
-- _conditions"), el df.apply(axis=1) que corre fila por fila en Python
-- sobre ~4.2M filas -- la parte más lenta y más propensa a "colgarse"
-- del notebook actual. Es lógicamente equivalente a comparar contra el
-- acumulado del mes anterior, que acá es LAG()/SUM() OVER() directo.
--
-- Puerto regla por regla desde el notebook real (no adivinado). El
-- sentinel -111 que usa pandas (porque NaN no compara bien con ==) se
-- reemplaza por NULL/IS NULL, el equivalente idiomático en SQL -- mismo
-- comportamiento, sin necesidad del truco.
--
-- BUG ENCONTRADO Y CORREGIDO respecto al legacy: la rama "compró en las
-- 3 sucursales" del notebook original dice
--   elif row["R1_acumulado"] != 0 and row["R1_acumulado"] != 0 and row["R2_acumulado"] != 0:
-- (chequea R1_acumulado DOS veces, nunca SL_acumulado -- típico
-- copy-paste). Efecto real: cualquier cliente con actividad en R1 y R2
-- caía en "Cliente SL, R1 y R2" sin importar si compró en SL o no,
-- mezclándose con "Cliente Dual R1 y R2". Evidencia en el propio
-- value_counts() del notebook: "Cliente SL, R1 y R2" = 463.626 casos vs.
-- "Cliente Dual R1 y R2" = apenas 1.302 -- desproporción que cuadra
-- exactamente con este bug. Acá se corrige (chequea SL_acumulado
-- también). ES UNA DIFERENCIA INTENCIONAL respecto al legacy -- no
-- esperar que el value_counts() coincida 1:1 en "Cliente SL, R1 y R2" /
-- "Cliente Dual R1 y R2" al comparar; sí debería coincidir la suma de
-- ambas categorías. Confirmar con el equipo de negocio antes del
-- cutover (Fase 6) que corregir esto es lo que quieren -- no se asume.
--
-- Los 16 tipo_cliente observados en el notebook real (value_counts())
-- están todos cubiertos acá -- ver test accepted_values en el schema.yml.

{{ config(materialized='table') }}

with base as (
    -- Mismo filtro que el notebook (celda que hace
    -- df.drop(df[(df["SL"]==0)&(df["R1"]==0)&(df["R2"]==0)].index)),
    -- aplicado antes en vez de después: no tiene sentido clasificar un
    -- mes sin ninguna compra en ninguna sucursal.
    select
        cliente_id_limpio,
        anio,
        mes,
        SL,
        R1,
        R2
    from {{ ref('fct_ventas_36m_pivotado') }}
    where not (SL = 0 and R1 = 0 and R2 = 0)
),

acumulado as (
    select
        cliente_id_limpio,
        anio,
        mes,
        SL,
        R1,
        R2,
        sum(SL) over (
            partition by cliente_id_limpio
            order by anio, mes
            rows between unbounded preceding and current row
        ) as sl_acumulado,
        sum(R1) over (
            partition by cliente_id_limpio
            order by anio, mes
            rows between unbounded preceding and current row
        ) as r1_acumulado,
        sum(R2) over (
            partition by cliente_id_limpio
            order by anio, mes
            rows between unbounded preceding and current row
        ) as r2_acumulado
    from base
),

con_prev as (
    select
        *,
        lag(sl_acumulado) over (partition by cliente_id_limpio order by anio, mes) as sl_acumulado_prev,
        lag(r1_acumulado) over (partition by cliente_id_limpio order by anio, mes) as r1_acumulado_prev,
        lag(r2_acumulado) over (partition by cliente_id_limpio order by anio, mes) as r2_acumulado_prev
    from acumulado
)

select
    cliente_id_limpio,
    anio,
    mes,
    SL,
    R1,
    R2,
    sl_acumulado,
    r1_acumulado,
    r2_acumulado,
    case
        -- Primer registro del cliente (LAG = NULL, antes -111 en pandas).
        when sl_acumulado_prev is null then
            case
                when sl_acumulado > 0 and r1_acumulado > 0 and r2_acumulado > 0 then 'Cliente SL, R1 y R2'
                when sl_acumulado > 0 and r1_acumulado > 0 then 'Cliente Dual SL y R1'
                when sl_acumulado > 0 and r2_acumulado > 0 then 'Cliente Dual SL y R2'
                when r1_acumulado > 0 and r2_acumulado > 0 then 'Cliente Dual R1 y R2'
                when sl_acumulado > 0 then 'Cliente SL'
                when r1_acumulado > 0 then 'Cliente R1'
                when r2_acumulado > 0 then 'Cliente R2'
            end

        -- Migración desde SL: el acumulado de SL no se movió este mes y
        -- el cliente no tenía actividad previa en R1 ni R2.
        when sl_acumulado = sl_acumulado_prev and r1_acumulado_prev = 0 and r2_acumulado_prev = 0 then
            case
                when r1_acumulado > 0 and r2_acumulado = 0 then 'Migro de SL a R1'
                when r1_acumulado = 0 and r2_acumulado > 0 then 'Migro de SL a R2'
                when r1_acumulado > 0 and r2_acumulado > 0 then 'Migro de SL a R1 y R2'
                else 'Cliente SL'
            end

        -- Migración desde R1.
        when r1_acumulado = r1_acumulado_prev and sl_acumulado_prev = 0 and r2_acumulado_prev = 0 then
            case
                when sl_acumulado > 0 and r2_acumulado = 0 then 'Migro de R1 a SL'
                when sl_acumulado = 0 and r2_acumulado > 0 then 'Migro de R1 a R2'
                when sl_acumulado > 0 and r2_acumulado > 0 then 'Migro de R1 a SL y R2'
                else 'Cliente R1'
            end

        -- Migración desde R2.
        when r2_acumulado = r2_acumulado_prev and sl_acumulado_prev = 0 and r1_acumulado_prev = 0 then
            case
                when sl_acumulado > 0 and r1_acumulado = 0 then 'Migro de R2 a SL'
                when sl_acumulado = 0 and r1_acumulado > 0 then 'Migro de R2 a R1'
                when sl_acumulado > 0 and r1_acumulado > 0 then 'Migro de R2 a SL y R1'
                else 'Cliente R2'
            end

        -- Clientes estables (sin patrón de migración detectado arriba).
        -- CORREGIDO respecto al legacy: acá SÍ se chequea sl_acumulado
        -- (ver nota de bug al principio del archivo).
        when sl_acumulado <> 0 and r1_acumulado <> 0 and r2_acumulado <> 0 then 'Cliente SL, R1 y R2'
        when sl_acumulado <> 0 and r1_acumulado <> 0 then 'Cliente Dual SL y R1'
        when sl_acumulado <> 0 and r2_acumulado <> 0 then 'Cliente Dual SL y R2'
        when r1_acumulado <> 0 and r2_acumulado <> 0 then 'Cliente Dual R1 y R2'
        when sl_acumulado <> 0 then 'Cliente SL'
        when r1_acumulado <> 0 then 'Cliente R1'
        when r2_acumulado <> 0 then 'Cliente R2'
    end as tipo_cliente
from con_prev
