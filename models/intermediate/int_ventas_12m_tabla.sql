-- La venta de los últimos 12 meses cerrados, a grano de línea,
-- materializada. Es el modelo que consumen los marts de Mayoristas y Top 300
-- y la tabla Ventas del tablero de Power BI.
--
-- POR QUÉ ES UNA TABLA. Su ventana sale de fecha_corte_mes_cerrado(), que
-- expande a getdate(). Como vista se recalcularía en cada consulta, y el
-- primero de cada mes empezaría a devolver un mes distinto sin que nadie
-- haya corrido nada.
--
-- Eso no molestaba mientras el único consumidor era dbt, porque dentro de
-- una misma corrida todos los modelos ven la misma ventana. Molesta desde
-- que Power BI importa las mismas filas: las tablas de marts_mayoristas
-- guardan la ventana del día en que se construyeron, así que entre el cambio
-- de mes y la corrida siguiente de dbt el tablero mostraría clientes que
-- existen en la venta y no tienen clasificación, y fechas que no están en el
-- calendario. Medido el 01/09/2026 con una versión anterior que era vista:
-- devolvía desde 2025-09-01 mientras las tablas cubrían desde 2025-08-01, con
-- 2.224 clientes de diferencia.
--
-- Además evita que cada consumidor recorra de nuevo la cadena de vistas sobre
-- dbo.Ventas_pos (238M+ filas). Siete modelos de dos proyectos leen esta
-- tabla: sin materializarla serían siete recorridos por corrida en lugar de
-- uno.
--
-- LAS COLUMNAS SE LISTAN A PROPÓSITO. Una vista que hace `select *` sobre
-- otra guarda la lista de columnas del momento en que se creó y no la
-- actualiza sola cuando la de abajo gana una columna. Pasó dos veces, con
-- tipo_persona y con medio_pago, y las columnas nuevas no llegaban hasta
-- correr `sp_refreshview` a mano. Por eso este modelo lee int_ventas_elegibles
-- directo, sin una vista en el medio, y nombra cada columna: si
-- int_ventas_elegibles gana una, hay que agregarla acá y en
-- int_ventas_24m_tabla para que llegue a los consumidores.
--
-- La regla de qué es un mes cerrado vive en un solo lugar,
-- fecha_corte_mes_cerrado(). Lo propio de este modelo es cuántos meses mira.
--
-- El adaptador crea las tablas como clustered columnstore por defecto
-- (as_columnstore), así que 62 millones de filas y diez columnas comprimen
-- mucho más de lo que sugiere el número.
--
-- CUÁNDO SE CONSTRUYE. Congelar la ventana no arregla por sí solo que dos
-- DAGs con cadencias distintas la reconstruyan: el semanal de Top 300 y el
-- mensual de Mayoristas pasan los dos por acá. Dentro de un mismo mes la
-- ventana no cambia, así que el desfase de período no vuelve a aparecer, pero
-- sí puede entrar venta de días que ya estaban dentro de la ventana y
-- llegaron tarde a la fuente. Por eso el tablero acota además al rango que
-- tienen las tablas de marts_mayoristas.

{{ config(materialized='table') }}

select
    cliente_id,
    cliente_id_limpio,
    producto_id,
    pdv_id,
    fecha_venta,
    venta_gs,
    unidades,
    medio_pago,
    ticket_id,
    tipo_persona
from {{ ref('int_ventas_elegibles') }}
where fecha_venta >= dateadd(month, -{{ var('ventana_meses_12m') }}, {{ fecha_corte_mes_cerrado() }})
  and fecha_venta <  {{ fecha_corte_mes_cerrado() }}
