-- Reemplaza los pasos 8-10 de canibalizacion_v3.py: clasifica cada
-- combinación cliente-sucursal (Único / Dual / Migración), 1 fila por
-- evento -- mismo grano que df_eventos en el script.
--
-- LÓGICA PORTADA 1:1 -- incluye 2 detalles no obvios del código Python
-- que hay que preservar para que el resultado coincida:
--
-- 1) DESEMPATE cuando un cliente compra en 2+ sucursales el MISMO mes
--    (su primer mes de actividad): pandas ordena por
--    primer_periodo_sucursal y, en empate, por el orden que trae
--    groupby(['cliente_id_limpio','Sucursal']) -- que agrupa por
--    Sucursal en orden alfabético (R1 < R2 < SL). Acá se replica ese
--    desempate explícito: order by primer_periodo_sucursal, sucursal.
--    Efecto real: la categoría "Nuevo - Dual" (11.210 casos en la
--    corrida real del script) sale exactamente de este caso -- 2
--    sucursales con primer_periodo_sucursal igual al primer mes del
--    cliente.
--
-- 2) `local_origen` es SIEMPRE la primera sucursal del cliente (nunca se
--    actualiza entre saltos -- ver la nota de diseño pendiente de
--    confirmar en canibalizacion_v3.ipynb/.py). Y "meses sin comprar en
--    el origen" para CADA salto se calcula buscando la compra MÁS
--    RECIENTE en esa sucursal de origen ANTES del mes del salto puntual
--    -- no el último período agregado de esa sucursal en toda la
--    ventana, que podría ser posterior si el cliente siguió comprando
--    ahí después de un primer salto. Portado como un lookup "as of"
--    (OUTER APPLY) contra fct_canibalizacion_evolutivo_cliente, no como
--    join a un MIN/MAX pre-agregado -- un agregado simple daría un
--    resultado distinto si el cliente vuelve a comprar en el origen
--    después de migrar y antes de un segundo salto.
--
-- tipo_cliente = 'Nuevo - Unico' hardcodeado en caso_unico (no un
-- CASE): se puede probar que la sucursal de origen SIEMPRE tiene su
-- primer_periodo_sucursal igual al primer período del cliente en toda
-- la ventana (por construcción -- es la sucursal con el período más
-- chico de todas), así que tipo_evento_origen es siempre 'Nuevo'.
-- Confirmado contra el value_counts() real del script: no existe
-- "Recurrente - Unico" en los datos.

{{ config(materialized='table') }}

with sucursales_cliente as (
    select
        cliente_id_limpio,
        sucursal,
        min(periodo) as primer_periodo_sucursal
    from {{ ref('fct_canibalizacion_evolutivo_cliente') }}
    group by cliente_id_limpio, sucursal
),

ordenado as (
    select
        *,
        row_number() over (
            partition by cliente_id_limpio
            order by primer_periodo_sucursal, sucursal
        ) as orden_sucursal,
        count(*) over (partition by cliente_id_limpio) as total_sucursales
    from sucursales_cliente
),

origen as (
    -- sucursal_0: la primera sucursal de cada cliente (con el desempate
    -- alfabético documentado arriba). Fija -- no se actualiza entre saltos.
    select
        cliente_id_limpio,
        sucursal            as sucursal_origen,
        primer_periodo_sucursal as primer_periodo_origen
    from ordenado
    where orden_sucursal = 1
),

caso_unico as (
    -- Clientes que solo compraron en 1 sucursal en toda la ventana --
    -- mismo criterio que `if len(sucursales_cliente) == 1` en el script.
    select
        cliente_id_limpio,
        'Nuevo - Unico' as tipo_cliente,
        sucursal            as local_origen,
        sucursal            as local_destino,
        primer_periodo_sucursal as periodo_evento,
        (primer_periodo_sucursal / 100) as anio,
        (primer_periodo_sucursal % 100) as mes
    from ordenado
    where total_sucursales = 1
),

destinos as (
    -- 1 fila por sucursal adicional (destino) -- mismo criterio que
    -- `for _, fila_destino in sucursales_cliente.iloc[1:]` en el script.
    select
        o.cliente_id_limpio,
        org.sucursal_origen,
        org.primer_periodo_origen,
        o.sucursal          as local_destino,
        o.primer_periodo_sucursal as primer_destino
    from ordenado o
    inner join origen org
        on o.cliente_id_limpio = org.cliente_id_limpio
    where o.total_sucursales > 1
      and o.orden_sucursal > 1
),

destinos_con_origen_previo as (
    select
        d.*,
        origen_antes.ultimo_periodo_origen
    from destinos d
    outer apply (
        select top 1 ev.periodo as ultimo_periodo_origen
        from {{ ref('fct_canibalizacion_evolutivo_cliente') }} ev
        where ev.cliente_id_limpio = d.cliente_id_limpio
          and ev.sucursal = d.sucursal_origen
          and ev.periodo < d.primer_destino
        order by ev.periodo desc
    ) as origen_antes
),

casos_migracion as (
    select
        cliente_id_limpio,
        concat(
            case when primer_destino = primer_periodo_origen then 'Nuevo' else 'Recurrente' end,
            ' - ',
            case
                when ultimo_periodo_origen is null then 'Dual'
                when {{ meses_entre_periodos('primer_destino', 'ultimo_periodo_origen') }}
                     > {{ var('canibalizacion_v3_meses_migracion') }} then 'Migracion'
                else 'Dual'
            end
        ) as tipo_cliente,
        sucursal_origen as local_origen,
        local_destino,
        primer_destino  as periodo_evento,
        (primer_destino / 100) as anio,
        (primer_destino % 100) as mes
    from destinos_con_origen_previo
),

eventos as (
    select * from caso_unico
    union all
    select * from casos_migracion
),

con_monto as (
    -- Monto que el cliente gastó en local_destino en el mes del evento
    -- -- mismo merge que el paso 10 del script.
    select
        e.*,
        ev.monto as monto_total
    from eventos e
    left join {{ ref('fct_canibalizacion_evolutivo_cliente') }} ev
        on e.cliente_id_limpio = ev.cliente_id_limpio
       and e.periodo_evento = ev.periodo
       and e.local_destino = ev.sucursal
)

select
    cliente_id_limpio,
    tipo_cliente,
    local_origen,
    local_destino,
    periodo_evento,
    anio,
    mes,
    monto_total
from con_monto
