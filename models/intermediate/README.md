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

**`int_ventas_12m`** aplica la ventana móvil de doce meses cerrados sobre
`int_ventas_elegibles`. Es una vista, así que su ventana se recalcula cada vez
que alguien la consulta.

**`int_ventas_12m_tabla`** son esas mismas filas, materializadas. Es la que
consumen los marts y el tablero de Power BI, por dos motivos. Congela la ventana
entre corridas de dbt, cosa que la vista no puede hacer: al pasar de un mes al
siguiente empieza a devolver otro período sin que nadie haya corrido nada, y eso
deja las tablas de `marts_mayoristas` desalineadas contra la venta que ve Power
BI. Y evita que cada consumidor vuelva a recorrer la cadena de vistas sobre
`dbo.Ventas_Ahorrazo`, que tiene más de 238 millones de filas: son ocho recorridos
por corrida contra uno solo.

La regla de la ventana vive únicamente en el macro `fecha_corte_mes_cerrado()`.
`int_ventas_12m_tabla` lee la vista entera en lugar de repetir el filtro, así que
si algún día cambia el criterio de meses cerrados, se cambia el macro y todo lo
demás lo hereda.
