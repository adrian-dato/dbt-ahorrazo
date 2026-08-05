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

select *
from {{ ref('int_ventas_elegibles') }}
where fecha_venta >= dateadd(month, -{{ var('ventana_meses_12m') }}, {{ fecha_corte_mes_cerrado() }})
  and fecha_venta <  {{ fecha_corte_mes_cerrado() }}
