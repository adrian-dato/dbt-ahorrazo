{{ config(severity='warn') }}

-- La venta diaria por categoría y la venta mensual de Canibalización salen de
-- la misma fuente, int_ventas_elegibles, con la misma ventana. Mes a mes tienen
-- que sumar lo mismo; el test avisa de los meses donde se separan más de 0,01%.
--
-- Un mes que no coincide suele ser uno de estos tres casos: una de las dos
-- tablas se reconstruyó y la otra no (la ventana o los datos son de días
-- distintos), un mes quedó con un monto parcial por una corrida incremental
-- que no cubrió el mes entero, o una de las dos perdió ventas en un join. Por
-- eso conviene mirar cuál de las dos se desvió de la fuente antes de
-- corregir.
--
-- Solo compara los meses que están en las dos tablas. La diferencia mínima
-- que tolera es por el redondeo: una suma en float y la otra en decimal.

with diaria as (
    select
        year(fecha_venta)  as anio,
        month(fecha_venta) as mes,
        sum(venta_gs)      as venta_diaria
    from {{ ref('fct_ventas_diarias_categoria_36m') }}
    group by year(fecha_venta), month(fecha_venta)
),

mensual as (
    select
        anio,
        mes,
        sum(total_ventas) as venta_mensual
    from {{ ref('fct_ventas_36m') }}
    group by anio, mes
)

select
    d.anio,
    d.mes,
    d.venta_diaria,
    m.venta_mensual,
    d.venta_diaria - m.venta_mensual as diferencia
from diaria d
inner join mensual m
    on d.anio = m.anio
   and d.mes  = m.mes
where abs(d.venta_diaria - m.venta_mensual) > 0.0001 * abs(m.venta_mensual)
