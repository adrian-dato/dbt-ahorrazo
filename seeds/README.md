# seeds/

Datos de referencia versionados en Git, en lugar de valores escritos dentro de
una consulta SQL o de una celda de notebook.

`dim_sucursal_mapeo.csv` traduce `pdv_id` a código y nombre de sucursal. Viene de
`canibalizacion_ahorrazo/seeds/` y reemplaza el `PIVOT ... FOR pdv_id IN ([3],[5],[6])`
que estaba escrito a mano en las consultas.

`productos_excluidos.csv` tiene los trece `producto_id` que el equipo comercial
aparta del análisis. Salieron de la lista `excluir_producto_id` de
`top_300_productos.ipynb`, copiados uno por uno. Antes esa lista la usaba solo
Top 300; ahora la aplican los tres proyectos a través de `int_ventas_elegibles`.

`clientes_excluidos.csv` tiene los clientes, por `cliente_id_limpio`, que no
entran en ningún análisis: el cliente de prueba `44444401` y los que pidieron
sacar los stakeholders, con el motivo en cada fila. `int_ventas_elegibles`
descarta sus ventas. Siguen en el catálogo de clientes, porque sacarlos de ahí no
los saca de los análisis: las ventas no pasan por el catálogo. Para sumar o quitar
un cliente se edita el CSV y se hace commit, nunca a mano en el servidor.
