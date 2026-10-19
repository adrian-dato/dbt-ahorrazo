# intermediate/

Reglas de negocio compartidas por los tres proyectos. Un modelo que sea
específico de canibalización, top 300 o mayoristas va en `marts/<proyecto>/`.

## Los modelos

**`int_clientes_normalizados`**, **`int_clientes_mapeo_limpio`** e
**`int_clientes_limpio`** resuelven la identidad del cliente: normalizan el
identificador, colapsan los duplicados y arman el catálogo con nombre, documento
y contacto. Incluyen correcciones que salieron de perfilar los datos reales
(símbolos sueltos en los extremos, separadores no estándar, clientes sin
identificación válida). El detalle de cada regla está comentado en
`int_clientes_mapeo_limpio.sql`.

Ya reemplazaron al proceso legacy: `stg_clientes_mapeo` y `stg_clientes_limpio`
repuntan a `int_clientes_mapeo_limpio` e `int_clientes_limpio` desde la Fase 2
(confirmada contra la base real), y ningún modelo del proyecto vuelve a leer
`dbo.clientes_mapeo`/`dbo.clientes_limpio`.

**`int_ventas_elegibles`** define qué es una venta válida para análisis, y es el
único lugar donde vive esa definición. Antes estaba escrita tres veces, de tres
formas distintas. Toma las exclusiones de producto de `int_productos_limpio` y
agrega la del cliente de prueba.

**`int_productos_limpio`** es el catálogo de productos elegibles, con las
categorías ya resueltas. Materializado como tabla porque se une contra
`stg_ventas` y recalcularlo en cada corrida saldría caro. Trae también una
clave por categoría en cada uno de los cuatro niveles (`categoria_key_n1` a
`categoria_key_n4`).

**`int_categorias`** es la tabla de esas claves: una fila por categoría de cada
nivel, con la clave de su padre y su ruta legible. Existe porque el nombre de una
categoría no la identifica. "Dama" aparece bajo 81 categorías de nivel 3
distintas, y 8 nombres de nivel 2, 99 de nivel 3 y 324 de nivel 4 se repiten bajo
más de un padre. La clave es el hash de la ruta completa, así que dos categorías
con el mismo nombre y distinto padre tienen claves distintas, y una categoría
nueva no mueve las existentes. Un nivel sin valor (el comodín `sin asignar.`
afecta a 59.028 productos en `categoria_4`) es un nodo `(sin asignar)` bajo su
padre, de modo que todo producto tiene clave en los cuatro niveles.
`categoria_4_limpio` no sirve para esto: mezcla nombres de dos niveles en la
misma columna.

**`int_ventas_12m_tabla`** es la venta de los últimos doce meses cerrados a grano
de línea, materializada. La consumen los marts de Mayoristas y Top 300 y el
tablero de Power BI, y es tabla por dos motivos. Congela la ventana entre
corridas de dbt: una vista, al pasar de un mes al siguiente, empezaría a devolver
otro período sin que nadie haya corrido nada, y eso dejaría las tablas de
`marts_mayoristas` desalineadas contra la venta que ve Power BI. Y evita que cada
consumidor vuelva a recorrer la cadena sobre `dbo.Ventas_Ahorrazo`, que tiene más
de 238 millones de filas: son ocho recorridos por corrida contra uno solo.

Lee `int_ventas_elegibles` directo, sin una vista en el medio, y lista sus
columnas. Antes había una vista intermedia, `int_ventas_12m`, que hacía
`select *`, y SQL Server guarda la lista de columnas de una vista cuando se crea:
las columnas nuevas de `int_ventas_elegibles` no le llegaban hasta correr
`sp_refreshview` a mano. Ahora, una columna nueva hay que agregarla en
`int_ventas_12m_tabla` y en `int_ventas_24m_tabla`.

**`int_ventas_24m_tabla`** es lo mismo con veinticuatro meses, para las preguntas
de tendencia que necesitan comparar un año contra el anterior.

La regla de qué es un mes cerrado vive únicamente en el macro
`fecha_corte_mes_cerrado()`. Cada tabla de ventas solo decide cuántos meses mira,
así que si algún día cambia el criterio, se cambia el macro y todo lo demás lo
hereda.
