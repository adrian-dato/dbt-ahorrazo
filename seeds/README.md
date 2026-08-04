# seeds/

Datos de referencia versionados en Git, en vez de literales hardcodeados
en SQL o en celdas de notebook.

- `dim_sucursal_mapeo.csv` — portado desde `canibalizacion_ahorrazo/seeds/`
  (mapeo `pdv_id` → `sucursal_codigo`/`sucursal_nombre`; reemplaza el
  `PIVOT ... FOR pdv_id IN ([3],[5],[6])` hardcodeado). Los nombres reales
  de sucursal siguen como `TODO` en el CSV, pendiente de completar.
- `productos_excluidos.csv` — a crear en Fase 3, junto con
  `int_ventas_elegibles`; unifica la lista hoy hardcodeada en
  `top_300_productos.ipynb`.
