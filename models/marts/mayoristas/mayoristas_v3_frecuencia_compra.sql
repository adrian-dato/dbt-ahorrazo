-- Para qué sirve: cada cuánto viene cada cliente. Grano
-- cliente_id_limpio, una fila por cliente de mayoristas_v3_resumen.
--
-- Es una segunda dimensión de segmentación, cruzable con el nivel: un
-- cliente Alto que viene todas las semanas y uno que viene una vez al
-- mes son dos situaciones comerciales distintas, y la clasificación
-- mayorista sola los trata igual.
--
-- Lee de mayoristas_v3_tickets_unidad (8,0M filas ya materializadas) y
-- no de int_ventas_12m (62M): la diferencia entre las dos, medida
-- contra la base, es de 2.477 tickets sobre 4.681.477 -- un 0,05%.
-- Esos son tickets compuestos ENTERAMENTE por Blis, Metros o Ramo, las
-- tres unidades que v3 deja fuera de C1/C2. Para clasificar cada
-- cuánto viene un cliente, una visita es una visita sin importar qué
-- unidad de medida tenía la canasta, así que ese 0,05% no mueve
-- ninguna clasificación -- y evita un escaneo más de la fact completa
-- en la corrida diaria.
--
-- El LEFT JOIN desde mayoristas_v3_resumen es para que ningún cliente
-- quede sin fila: los poquísimos que solo compraron en esas 3 unidades
-- salen con 'Sin datos' en vez de desaparecer del modelo.
--
-- ---------------------------------------------------------------
-- CÓMO SE CALCULA, EN CRIOLLO
--
-- Si un cliente compró por primera vez el 1 de enero, por última vez
-- el 31 de diciembre, y en el medio vino 25 veces, entonces entre esas
-- 25 visitas hubo 24 intervalos:
--
--     365 días / 24 intervalos = 15 días entre visita y visita
--
-- Ese cliente es quincenal.
--
--     dias_entre_visitas = (última compra - primera compra)
--                          / (visitas - 1)
--
-- El "menos uno" es lo único que tiene truco, y es el problema de los
-- postes del alambrado: con 25 postes hay 24 tramos de alambre, no 25.
--
-- POR QUÉ NO SE MIDE CADA INTERVALO POR SEPARADO
--
-- Porque da EXACTAMENTE el mismo número, no uno parecido. La suma de
-- los intervalos consecutivos es
--
--     (d2 - d1) + (d3 - d2) + ... + (dn - dn-1)
--
-- y todo lo del medio se cancela: queda dn - d1, que es el span.
-- Dividido por la cantidad de intervalos, es esta misma cuenta. No es
-- una aproximación: es la misma fórmula escrita de forma barata, sin
-- LAG y sin ordenar 8M de filas particionadas por cliente -- que es
-- justo la clase de operación que ya colgó esta instancia dos veces.
--
-- LO QUE ESTA CUENTA NO VE
--
-- Un promedio suaviza las ráfagas. Un cliente que vino 20 veces en una
-- semana y una sola vez 11 meses después da ~18 días de promedio y sale
-- "Quincenal", cuando en realidad fue una ráfaga más un rezagado. Para
-- la pregunta del negocio -- "¿este cliente vuelve seguido?" -- el
-- promedio alcanza. Si algún día hace falta distinguir la ráfaga del
-- hábito, eso es la MEDIANA de los intervalos, y esa sí necesita LAG.
-- ---------------------------------------------------------------
--
-- Los cortes (10 / 20 / 45 días) van en dbt_project.yml. A diferencia
-- de los umbrales de la clasificación, NO son percentiles del dato:
-- semana, quincena y mes son conceptos del negocio. Conviene
-- confirmarlos con el equipo comercial, no calibrarlos.

{{ config(materialized='table') }}

-- Una visita es un DIA con compra, no una factura. La version anterior
-- contaba count(distinct ticket_id) y lo llamaba visitas, y no es lo
-- mismo: un cliente que se lleva kilos y unidades en dos facturas del
-- mismo dia, o que pasa dos veces por la caja, sumaba dos visitas
-- habiendo venido una sola vez. El denominador quedaba inflado y el
-- cliente salia mas frecuente de lo que es.
--
-- Las facturas se siguen contando, en su propia columna. El cociente
-- entre las dos dice cuanto se parten las facturas de ese cliente.
with actividad as (

    select
        cliente_id_limpio,
        count(distinct fecha_venta) as visitas,
        count(distinct ticket_id)   as facturas,
        min(fecha_venta)            as primera_compra,
        max(fecha_venta)            as ultima_compra
    from {{ ref('mayoristas_v3_tickets_unidad') }}
    group by cliente_id_limpio

),

base as (

    select
        r.cliente_id_limpio,
        isnull(v.visitas, 0)  as visitas,
        isnull(v.facturas, 0) as facturas,
        v.primera_compra,
        v.ultima_compra,
        datediff(day, v.primera_compra, v.ultima_compra) as dias_activo
    from {{ ref('mayoristas_v3_resumen') }} r
    left join actividad v
        on r.cliente_id_limpio = v.cliente_id_limpio

)

select
    cliente_id_limpio,
    visitas,
    facturas,
    primera_compra,
    ultima_compra,
    dias_activo,
    -- Dias entre la primera y la ultima compra, divididos por la cantidad
    -- de intervalos. Entre V visitas hay V-1 intervalos: es el problema de
    -- los postes del alambrado, con 25 postes hay 24 tramos de alambre.
    --
    -- No es una aproximacion. Medir cada intervalo por separado y
    -- promediarlos da exactamente este numero: al sumar
    -- (d2-d1) + (d3-d2) + ... + (dn-dn-1) todo lo del medio se cancela y
    -- queda dn - d1. Es la misma cuenta escrita barata, sin LAG y sin
    -- ordenar millones de filas particionadas por cliente.
    --
    -- Lo que la cuenta NO ve: un promedio no distingue un habito de una
    -- rafaga. Un cliente que vino 20 veces en una semana y una sola vez
    -- 11 meses despues da ~18 dias y sale Quincenal. Para "vuelve
    -- seguido?" alcanza; para "es regular?" haria falta la mediana de los
    -- intervalos, y eso si necesita LAG.
    --
    -- nullif evita dividir por cero con una sola visita: ahi no hay
    -- ningun intervalo que medir.
    dias_activo * 1.0 / nullif(visitas - 1, 0) as dias_entre_visitas,
    case
        when visitas = 0 then 'Sin datos'
        -- Un solo dia con compra, sin importar cuantas facturas emitio
        -- ese dia: no hay intervalo que medir.
        when visitas = 1 then 'Visita única'
        when dias_activo * 1.0 / (visitas - 1) <= {{ var('frecuencia_semanal_dias') }}
            then 'Semanal'
        when dias_activo * 1.0 / (visitas - 1) <= {{ var('frecuencia_quincenal_dias') }}
            then 'Quincenal'
        when dias_activo * 1.0 / (visitas - 1) <= {{ var('frecuencia_mensual_dias') }}
            then 'Mensual'
        else 'Esporádico'
    end as frecuencia_compra
from base
