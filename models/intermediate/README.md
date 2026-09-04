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
`stg_ventas` y recalcularlo en cada corrida saldría caro.

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
