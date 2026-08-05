-- Ventana móvil de 12 meses sobre int_ventas_elegibles -- COMPARTIDA
-- entre Top 300 y Clientes Mayoristas, los 2 proyectos que hoy dependen
-- de la misma ventana en el legacy (view_ventas_ahorrazo_filtradas_12m,
-- todavía no portada del todo -- esto reemplaza su porción de ventana
-- temporal; las reglas de negocio/exclusiones ya viven en
-- int_ventas_elegibles, no se duplican acá).
--
-- Rolling de verdad: se calcula contra getdate() en cada corrida, no
-- contra fechas fijas como START_2025/END_2026 (hardcodeadas en
-- top_300_productos.ipynb) -- ya no hace falta editar nada a mano cada
-- mes para correr sobre el período correcto.
--
-- View, sin materializar: es un filtro liviano sobre un modelo que ya
-- resolvió el trabajo pesado (int_ventas_elegibles).

select *
from {{ ref('int_ventas_elegibles') }}
where fecha_venta >= dateadd(month, -{{ var('ventana_meses_12m') }}, getdate())
  and fecha_venta <  getdate()
