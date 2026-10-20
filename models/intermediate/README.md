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

Reemplazaron al proceso anterior, y ningún modelo del proyecto lee
`dbo.clientes_mapeo` ni `dbo.clientes_limpio`.

**`int_ventas_elegibles`** define qué es una venta válida para análisis, y es el
único lugar donde vive esa definición. Antes estaba escrita tres veces, de tres
formas distintas. Toma las exclusiones de producto de `int_productos_limpio` y
agrega la del cliente de prueba.

**`int_productos_limpio`** es el catálogo de productos elegibles, con las
categorías ya resueltas. Materializado como tabla porque se une contra
`stg_ventas` y recalcularlo en cada corrida saldría caro. Trae también una
clave por categoría en cada uno de los cuatro niveles (`categoria_key_n1` a
`categoria_key_n4`).

Las claves de categoría se leen en `marts_core.dim_categoria`, que tiene una fila por
categoría de cada nivel con su nombre y su ruta. Cada categoría se identifica por la
ruta completa y no por el nombre, porque "Dama" aparece bajo 81 categorías de nivel 3
distintas. El detalle está en el README de `marts/core/`.

**`int_ventas_12m_tabla`** es la venta de los últimos doce meses cerrados a grano
de línea, materializada. La consumen los marts de Mayoristas y Top 300 y el
tablero de Power BI, y es tabla por dos motivos. Congela la ventana entre
corridas de dbt: una vista, al pasar de un mes al siguiente, empezaría a devolver
otro período sin que nadie haya corrido nada, y eso dejaría las tablas de
`marts_mayoristas` desalineadas contra la venta que ve Power BI. Y evita que cada
consumidor vuelva a recorrer la cadena sobre `dbo.Ventas_pos`, que tiene más
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
