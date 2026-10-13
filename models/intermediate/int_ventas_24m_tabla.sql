-- La misma ventana de meses cerrados que int_ventas_12m_tabla, con las
-- mismas exclusiones (todo sale de int_ventas_elegibles), pero de 24
-- meses en vez de 12.
--
-- POR QUÉ EXISTE. Con 12 meses no se puede comparar un año contra el
-- anterior: la ventana entera ES el año. Cualquier pregunta de tendencia
-- interanual -- "¿bajó el consumo de panadería?", "¿esta categoría está
-- perdiendo clientes?" -- necesita los 24 meses para tener un período y
-- su comparable. Hoy eso se estaba respondiendo con
-- fct_ventas_agrupadas_24m, que sirve para categoría y marca pero ya
-- viene agregada a grano mes x cliente x sucursal x categoría: no tiene
-- producto_id ni unidad_medida, así que no permite bajar a producto ni
-- separar kilos de unidades. Este modelo mantiene el grano de línea.
--
-- MESES CERRADOS, igual que la de 12. Si se corre cualquier día del mes
-- en curso, la ventana llega hasta el último día del mes ANTERIOR. Con
-- fecha de corte en septiembre de 2026, eso es desde 2024-09-01 hasta
-- 2026-08-31. Nunca entra el mes en curso, que estaría a medio cargar y
-- haría parecer que la venta se derrumbó -- que es exactamente el error
-- que produce comparar tramos sin este cuidado.
--
-- POR QUÉ APLICA EL FILTRO ACÁ Y NO LEE UNA VISTA. int_ventas_12m_tabla
-- lee int_ventas_12m porque esa vista ya existía y se usa para consultas
-- a mano. Acá no hay vista equivalente y no hace falta uno: la regla de
-- "hasta el mes cerrado" sigue viviendo en un solo lugar, el macro
-- fecha_corte_mes_cerrado(); lo único propio de este modelo es cuántos
-- meses mira. Si algún día cambia el criterio de mes cerrado, se cambia
-- el macro y los dos modelos lo heredan.
--
-- CUÁNTO CUESTA. Es aproximadamente el doble de filas que la de 12 meses
-- (esa ronda los 62 millones) y recorre la fact de 238M+ filas el doble
-- de lejos hacia atrás. No está tagueada y ningún modelo le hace ref, así
-- que ningún selector por tag o por ancestro la alcanza: la construye una
-- tarea propia del DAG mensual (build_ventas_24m.py en
-- orquestacion_ahorrazo), después de la cadena de mayoristas. Mensual
-- alcanza porque con meses cerrados la ventana solo cambia el día 1.
--
-- OJO AL COMPARAR SUCURSALES EN EL PRIMER MES DE LA VENTANA. Ruta 2
-- (pdv_id = 6) abrió en septiembre de 2024, que es justo donde arranca la
-- ventana cuando el corte cae en septiembre de 2026. Ese mes no es
-- comparable contra los demás para esa sucursal.

{{ config(materialized='table') }}

select *
from {{ ref('int_ventas_elegibles') }}
where fecha_venta >= dateadd(month, -{{ var('ventana_meses_24m') }}, {{ fecha_corte_mes_cerrado() }})
  and fecha_venta <  {{ fecha_corte_mes_cerrado() }}
