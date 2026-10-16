{% macro clave_categoria(nivel, partes) %}
{#
    Clave de una categoría: el hash de su ruta completa desde la raíz,
    con el nivel como prefijo. 'N3-9F2A41C07B3D' es la ruta
    categoria_1 | categoria_2 | categoria_3.

    Un nombre no alcanza como identificador: 'Dama' aparece bajo 81
    categoria_3 distintas, y 8 nombres de categoria_2, 99 de categoria_3 y
    324 de categoria_4 se repiten bajo más de un padre. La ruta sí es
    única, porque dos categorías con el mismo nombre pero distinto padre
    tienen rutas distintas.

    El hash es estable: una categoría nueva no mueve las claves que ya
    existen. Un número correlativo se reasignaría con cada alta y rompería
    cualquier modelo de forecast guardado por categoría.

    12 caracteres hexadecimales son 48 bits: con unos 4.000 nodos por nivel
    la probabilidad de colisión ronda 3 en cien millones, y el test de
    unicidad de int_categorias la detectaría igual. Texto con prefijo y no
    un bigint porque un número de 19 dígitos se trunca al abrirlo en Excel
    y generaría duplicados falsos.

    `partes` son los textos ya pasados por normalizar_categoria(), del
    nivel 1 al nivel pedido. concat_ws exige al menos dos valores, así que
    el nivel 1, que tiene uno solo, se hashea directo.
#}
{%- set ruta = partes[0] if partes | length == 1 else "concat_ws(N'|', " ~ (partes | join(', ')) ~ ")" -%}
    concat(
        'N{{ nivel }}-',
        convert(
            char(12),
            substring(hashbytes('MD5', {{ ruta }}), 1, 6),
            2
        )
    )
{% endmacro %}
