-- La misma ventana de 12 meses cerrados que int_ventas_12m, pero
-- materializada. Es el modelo que consumen todos los marts y el tablero
-- de Power BI; la vista queda para consultas a mano.
--
-- POR QUÉ EXISTE. int_ventas_12m es una vista, y una vista no guarda
-- datos: guarda la consulta. Su ventana sale de fecha_corte_mes_cerrado(),
-- que expande a getdate(), así que se recalcula cada vez que alguien la
-- consulta. El primero de cada mes la vista empieza a devolver un mes
-- distinto sin que nadie haya corrido nada.
--
-- Eso no molestaba mientras el único consumidor era dbt, porque dentro de
-- una misma corrida todos los modelos ven la misma ventana. Molesta desde
-- que Power BI importa las mismas filas: las tablas de marts_mayoristas
-- guardan la ventana del día en que se construyeron y la vista sigue
-- corriéndose sola, así que entre el cambio de mes y la corrida siguiente
-- de dbt el tablero muestra clientes que existen en la venta y no tienen
-- clasificación, y fechas que no están en el calendario. Medido el
-- 01/09/2026: la vista devolvía desde 2025-09-01 y las tablas desde
-- 2025-08-01, con 2.224 clientes de diferencia.
--
-- POR QUÉ LEE LA VISTA Y NO REPITE EL FILTRO. La regla de la ventana
-- vive en un solo lugar, fecha_corte_mes_cerrado(), y así se queda. Este
-- modelo no la vuelve a escribir: toma la vista entera y la congela. Si
-- algún día cambia el criterio de "meses cerrados", se cambia el macro y
-- esto lo hereda sin tocarse.
--
-- POR QUÉ ADEMÁS CONVIENE. Siete modelos de dos proyectos hacían ref a la
-- vista, y como toda la cadena de arriba también son vistas
-- (int_ventas_elegibles sobre stg_ventas sobre dbo.Ventas_Ahorrazo,
-- 238M+ filas), cada uno de esos ref recorría la fact completa de nuevo.
-- Materializando acá, ese recorrido pasa a ser uno solo por corrida. El
-- comentario de int_mayoristas_v3_tickets_por_unidad ya peleaba contra
-- este mismo problema aguas abajo, modelo por modelo.
--
-- El adaptador crea las tablas como clustered columnstore por defecto
-- (as_columnstore), así que 62 millones de filas y nueve columnas
-- comprimen mucho más de lo que sugiere el número.
--
-- OJO CON CUÁNDO SE CONSTRUYE. Congelar la ventana no arregla por sí solo
-- que dos DAGs con cadencias distintas la reconstruyan: el DAG semanal de
-- Top 300 y el mensual de Mayoristas pasan los dos por acá. Dentro de un
-- mismo mes la ventana no cambia, así que el desfase de período no vuelve
-- a aparecer, pero sí puede entrar venta de días que ya estaban dentro de
-- la ventana y llegaron tarde a la fuente. Por eso el tablero acota
-- además al rango que tienen las tablas de marts_mayoristas.

{{ config(materialized='table') }}

select *
from {{ ref('int_ventas_12m') }}
