-- Reemplaza construir_top300_con_metricas() (top_300_productos.ipynb):
-- Puntaje Final (pesos = vars en dbt_project.yml, mismos valores que el
-- notebook), Top 300 por ámbito (GLOBAL y cada sucursal por separado),
-- y los buckets de unidades por ticket (Tickets_1-2/3-5/>=6).
--
-- Diferencia de implementación (no de resultado) respecto al notebook:
-- ahí los buckets se calculan SOLO para los productos que ya quedaron
-- en el Top 300, por eficiencia en pandas. Acá se calculan para todos
-- los productos sobre el umbral y se descartan al final -- en SQL
-- push-down no hace falta esa optimización, el resultado final es
-- idéntico.
--
-- Pendiente (no bloqueante, ver PENDIENTES.md): enriquecer con
-- metadata de producto (nombre/categoria/precio desde dbo.Productos)
-- -- el notebook lo hace en una celda aparte, no portado todavía.
--
-- cast(producto_id as varchar(100)) explícito en los JOIN de acá abajo:
-- aunque toda la cadena (stg_ventas -> int_ventas_elegibles ->
-- int_ventas_12m -> int_top300_kpis) ya castea producto_id a varchar,
-- seguía apareciendo el mismo error de conversión a int (245/248) en
-- este modelo puntual, con valores distintos cada vez ("1685-G",
-- luego "ICN9695") -- señal de que la resolución de tipos implícita de
-- SQL Server a través de varias vistas anidadas no es confiable acá.
-- Se fuerza el tipo en el JOIN mismo, sin depender de que se propague
-- solo desde arriba.

{{ config(materialized='table') }}

with kpis as (
    select * from {{ ref('int_top300_kpis') }}
),

puntaje as (
    select
        *,
        norm_ventas         * {{ var('top300_peso_ventas') }}
      + norm_tickets         * {{ var('top300_peso_tickets') }}
      + norm_unidades_dia    * {{ var('top300_peso_unidades_dia') }}
      + norm_unidades_ticket * {{ var('top300_peso_unidades_ticket') }} as puntaje_final
    from kpis
),

rankeado as (
    select
        *,
        -- producto_id como tercer criterio de desempate: sin esto, dos
        -- productos empatados en puntaje_final Y ventas no tienen un
        -- orden garantizado entre corridas (SQL Server no lo asegura),
        -- lo que puede correr la posición #300 de una corrida a otra sin
        -- que cambie ningún dato real -- rompe la idempotencia del
        -- ranking.
        row_number() over (
            partition by ambito
            order by puntaje_final desc, ventas desc, producto_id
        ) as posicion
    from puntaje
),

top300 as (
    select *
    from rankeado
    where posicion <= 300
),

ventas_top300 as (
    -- Unidades del producto dentro de cada ticket, solo para los
    -- productos que llegaron al Top 300 en su ámbito.
    select
        v.ambito,
        v.producto_id,
        v.unidades_ticket_producto
    from (
        select
            'GLOBAL' as ambito,
            e.producto_id,
            sum(e.unidades) as unidades_ticket_producto
        from {{ ref('int_ventas_12m') }} e
        group by e.producto_id, e.ticket_id

        union all

        select
            cast(e.pdv_id as varchar(50)) as ambito,
            e.producto_id,
            sum(e.unidades) as unidades_ticket_producto
        from {{ ref('int_ventas_12m') }} e
        group by e.pdv_id, e.producto_id, e.ticket_id
    ) v
    inner join top300 t
        on t.ambito = v.ambito
       and cast(t.producto_id as varchar(100)) = cast(v.producto_id as varchar(100))
),

buckets as (
    select
        ambito,
        producto_id,
        sum(case when unidades_ticket_producto between 1 and 2 then 1 else 0 end) as tickets_1_2,
        sum(case when unidades_ticket_producto between 3 and 5 then 1 else 0 end) as tickets_3_5,
        sum(case when unidades_ticket_producto >= 6 then 1 else 0 end)            as tickets_6_mas
    from ventas_top300
    group by ambito, producto_id
)

select
    t.ambito,
    t.producto_id,
    t.posicion,
    t.puntaje_final,
    t.norm_ventas,
    t.norm_tickets,
    t.norm_unidades_dia,
    t.norm_unidades_ticket,
    t.ventas,
    t.tickets_por_producto,
    t.unidades_totales,
    t.dias_con_ventas,
    t.unidades_por_ticket,
    t.unidades_por_dia,
    isnull(b.tickets_1_2, 0)   as tickets_1_2,
    isnull(b.tickets_3_5, 0)   as tickets_3_5,
    isnull(b.tickets_6_mas, 0) as tickets_6_mas
from top300 t
left join buckets b
    on t.ambito = b.ambito
   and cast(t.producto_id as varchar(100)) = cast(b.producto_id as varchar(100))
