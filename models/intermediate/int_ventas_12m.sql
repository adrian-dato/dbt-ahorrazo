-- Ventana móvil de 12 meses sobre int_ventas_elegibles -- COMPARTIDA
-- entre Top 300 y Clientes Mayoristas, los 2 proyectos que hoy dependen
-- de la misma ventana en el legacy (view_ventas_ahorrazo_filtradas_12m,
-- todavía no portada del todo -- esto reemplaza su porción de ventana
-- temporal; las reglas de negocio/exclusiones ya viven en
-- int_ventas_elegibles, no se duplican acá).
--
-- Rolling de verdad, en MESES CERRADOS: si se corre cualquier día del
-- mes actual, la ventana llega hasta el último día del mes ANTERIOR, no
-- hasta "ahora" -- mismo criterio que ya usaba
-- view_ventas_ahorrazo_filtradas_12m (CTE "limites") en el legacy,
-- portado acá vía el macro fecha_corte_mes_cerrado(). No usar getdate()
-- directo como límite superior -- mezclaría un mes en curso, parcial,
-- con meses ya cerrados.
--
-- View, sin materializar: es un filtro liviano sobre un modelo que ya
-- resolvió el trabajo pesado (int_ventas_elegibles).
--
-- OJO CON EL `select *` SI int_ventas_elegibles GANA UNA COLUMNA. SQL
-- Server resuelve el `*` de una vista a la lista de columnas que tenía el
-- objeto de abajo EN EL MOMENTO de crearla, y no la vuelve a resolver
-- sola cuando ese objeto cambia -- CREATE OR ALTER VIEW no alcanza.
-- Encontrado real: al agregar medio_pago a int_ventas_elegibles (y antes,
-- sin que nadie lo notara, con tipo_persona) esta vista siguió
-- devolviendo la lista vieja de columnas hasta correr
-- `EXEC sp_refreshview 'intermediate.int_ventas_12m'` a mano -- y
-- int_ventas_12m_tabla, que hace `select *` sobre ESTA vista, heredaba el
-- problema. Cualquier columna nueva en int_ventas_elegibles necesita ese
-- sp_refreshview antes (o en vez) de un simple `dbt build`.

select *
from {{ ref('int_ventas_elegibles') }}
where fecha_venta >= dateadd(month, -{{ var('ventana_meses_12m') }}, {{ fecha_corte_mes_cerrado() }})
  and fecha_venta <  {{ fecha_corte_mes_cerrado() }}
