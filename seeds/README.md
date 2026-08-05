# seeds/

Datos de referencia versionados en Git, en vez de literales hardcodeados
en SQL o en celdas de notebook.

- `dim_sucursal_mapeo.csv` — portado desde `canibalizacion_ahorrazo/seeds/`
  (mapeo `pdv_id` → `sucursal_codigo`/`sucursal_nombre`; reemplaza el
  `PIVOT ... FOR pdv_id IN ([3],[5],[6])` hardcodeado). Los nombres reales
  de sucursal siguen como `TODO` en el CSV, pendiente de completar.
- `productos_excluidos.csv` — hecho (Fase 3). Los 13 `producto_id` de
  `excluir_producto_id` en `top_300_productos.ipynb` (celda 916),
  copiados tal cual -- no reinventados. Unifica esa lista, antes solo
  usada por Top 300, para los 3 proyectos vía `int_ventas_elegibles`.
