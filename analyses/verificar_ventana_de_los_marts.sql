-- Que periodo cubre cada tabla del proyecto Mayoristas, y cuanto cambia
-- la frecuencia de compra al contar visitas como dias y no como facturas.
--
-- La primera consulta es la que hay que correr cada vez que un numero no
-- cierra. NO sirve mirar create_date ni modify_date en sys.objects: esas
-- columnas reflejan cambios de estructura, no de contenido -- una tabla
-- recargada entera puede seguir mostrando la fecha de la semana pasada.
-- La unica fuente confiable de "hasta cuando llegan los datos" es
-- preguntarle a los datos.
--
-- SQL plano contra los esquemas de dbt: se pega y se corre.


-- 1. La ventana de cada tabla. Todas tienen que dar el mismo rango. Si
--    una no coincide, es que no se reconstruyo con las otras, y ahi es
--    donde van a aparecer clientes sin nivel o fechas fuera del
--    calendario en el tablero.
select 'int_ventas_12m_tabla' as tabla,
       min(fecha_venta) as desde, max(fecha_venta) as hasta, count(*) as filas
from intermediate.int_ventas_12m_tabla

union all
select 'int_mayoristas_v3_tickets_por_unidad',
       min(fecha_venta), max(fecha_venta), count(*)
from marts_mayoristas.int_mayoristas_v3_tickets_por_unidad

union all
select 'mayoristas_v3_tickets_unidad',
       min(fecha_venta), max(fecha_venta), count(*)
from marts_mayoristas.mayoristas_v3_tickets_unidad

union all
select 'mayoristas_v3_frecuencia_compra',
       min(primera_compra), max(ultima_compra), count(*)
from marts_mayoristas.mayoristas_v3_frecuencia_compra

-- Y la de la vista, que se mueve sola con el calendario: si no coincide
-- con las de arriba, es que cambio el mes y todavia no se corrio dbt.
union all
select 'int_ventas_12m (vista)',
       min(fecha_venta), max(fecha_venta), null
from intermediate.int_ventas_12m;


-- 2. Cuanto se parten las facturas. visitas = dias distintos con compra,
--    facturas = tickets. Donde facturas > visitas, el cliente emitio mas
--    de una factura el mismo dia -- por unidades de medida distintas, por
--    pasar dos veces por la caja, o porque el sistema partio la venta.
--
--    Esos son exactamente los clientes a los que la version anterior del
--    modelo les inflaba el denominador y los hacia parecer mas frecuentes
--    de lo que son. Correr DESPUES del build con el modelo corregido.
select
    count(*)                                                   as clientes,
    sum(case when facturas > visitas then 1 else 0 end)        as con_facturas_partidas,
    cast(sum(case when facturas > visitas then 1 else 0 end) as float)
        / nullif(count(*), 0)                                  as pct,
    max(cast(facturas as float) / nullif(visitas, 0))          as peor_caso_facturas_por_dia,
    avg(cast(facturas as float) / nullif(visitas, 0))          as promedio_facturas_por_dia
from marts_mayoristas.mayoristas_v3_frecuencia_compra
where visitas > 0;


-- 3. Como quedo repartida la frecuencia. Comparar contra la distribucion
--    anterior dice cuantos clientes se movieron de banda por la
--    correccion -- se mueven hacia bandas MENOS frecuentes, nunca al
--    reves, porque el denominador solo puede bajar.
select
    frecuencia_compra,
    count(*)                                      as clientes,
    cast(count(*) as float) / sum(count(*)) over () as pct,
    avg(dias_entre_visitas)                       as dias_entre_visitas_promedio,
    avg(cast(visitas as float))                   as visitas_promedio,
    avg(cast(facturas as float))                  as facturas_promedio
from marts_mayoristas.mayoristas_v3_frecuencia_compra
group by frecuencia_compra
order by 2 desc;
