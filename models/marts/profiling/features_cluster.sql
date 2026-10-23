-- Entrada de la segmentación cualitativa (cluster.py, repo customer-profiling,
-- modo source_pivoted): una fila por cliente y una columna por feature,
-- armada desde el feature store (marts_core.fct_features_cliente).
--
-- POR QUÉ UNA TABLA ANCHA Y NO LOS PIVOTS DE cluster.py. El modo que arma los
-- pivots desde SQL usa GROUP BY 1,2, que SQL Server no admite. El modo
-- source_pivoted lee una tabla ya pivoteada con SELECT *.
--
-- QUÉ CATEGORÍAS ENTRAN. Las de nivel 3 que compra al menos el 1% de los
-- clientes (var cluster_cobertura_min_categoria). Al armarlo eran 414 de 999 y
-- cubrían el 97,7% de las apariciones de categoría en tickets. Las demás las
-- compran muy pocos clientes y para KMeans son ruido: columnas casi siempre en
-- cero que igual pesan en las distancias. Su presencia queda resumida en
-- "cat_(otras categorías)". La lista se calcula al construir el modelo, así que
-- se ajusta sola cuando cambian los datos. Medios de pago entran todos (25).
--
-- VALORES. La participación del feature store: la parte de los tickets del
-- cliente que incluye la categoría o el medio de pago. 0 si nunca la compró.
-- "cat_(otras categorías)" es la parte de sus tickets que incluye alguna
-- categoría fuera de la lista, contada por ticket para no sumar dos veces un
-- ticket con varias.
--
-- NOMBRES DE COLUMNA. Prefijo cat_ o pago_ y el nombre legible (la ruta de la
-- categoría o el medio de pago). cluster.py agrupa por prefijo al elegir qué
-- variables describen cada cluster, y Gemini lee estos nombres tal cual.
--
-- TIPOS. Todo float: cluster.py descarta las columnas que pandas no reconoce
-- como numéricas, y un decimal llega por pyodbc como objeto Decimal.
--
-- segmento_mayorista viaja en la tabla: cluster.py la toma como columna de
-- grupo (grouping.group_by_col) y entrena un modelo por segmento.

{{ config(materialized='table') }}

{% set umbral = var('cluster_cobertura_min_categoria', 0.01) %}

{% if execute %}
    {% set sql_categorias %}
        select feature_key, max(feature_nombre) as nombre
        from {{ ref('fct_features_cliente') }}
        where grupo = 'categoria_3'
        group by feature_key
        having count(*) >= {{ umbral }} * (select count(distinct cliente_id_limpio) from {{ ref('fct_features_cliente') }})
        order by max(feature_nombre)
    {% endset %}
    {% set sql_medios %}
        select feature_key, max(feature_nombre) as nombre
        from {{ ref('fct_features_cliente') }}
        where grupo = 'medio_pago'
        group by feature_key
        order by max(feature_nombre)
    {% endset %}
    {% set categorias = run_query(sql_categorias).rows %}
    {% set medios = run_query(sql_medios).rows %}
{% else %}
    {% set categorias = [] %}
    {% set medios = [] %}
{% endif %}

with features as (
    select cliente_id_limpio, grupo, feature_key, participacion
    from {{ ref('fct_features_cliente') }}
),

ancho as (
    select
        cliente_id_limpio
        {%- for fila in categorias %},
        cast(sum(case when grupo = 'categoria_3' and feature_key = N'{{ fila[0] | replace("'", "''") }}'
                      then participacion else 0 end) as float) as [cat_{{ fila[1] | replace(']', ']]') }}]
        {%- endfor %}
        {%- for fila in medios %},
        cast(sum(case when grupo = 'medio_pago' and feature_key = N'{{ fila[0] | replace("'", "''") }}'
                      then participacion else 0 end) as float) as [pago_{{ fila[1] | replace(']', ']]') }}]
        {%- endfor %}
    from features
    group by cliente_id_limpio
),

tickets as (
    select cliente_id_limpio, max(tickets_cliente) as tickets_cliente
    from {{ ref('fct_features_cliente') }}
    group by cliente_id_limpio
),

-- Tickets con alguna categoría fuera de la lista, contados una vez por ticket.
otras as (
    select v.cliente_id_limpio, count(distinct v.ticket_id) as tickets_otras
    from {{ ref('int_ventas_12m_tabla') }} v
    inner join {{ ref('int_productos_limpio') }} p
        on cast(p.producto_id as varchar(100)) = cast(v.producto_id as varchar(100))
    {%- if categorias %}
    where p.categoria_key_n3 collate database_default not in (
        {%- for fila in categorias %}N'{{ fila[0] | replace("'", "''") }}'{{ ", " if not loop.last }}{% endfor -%}
    )
    {%- endif %}
    group by v.cliente_id_limpio
)

select
    a.*,
    cast(1.0 * coalesce(o.tickets_otras, 0) / t.tickets_cliente as float) as [cat_(otras categorías)],
    coalesce(c.segmento_mayorista, 'Sin clasificar')                      as segmento_mayorista
from ancho a
inner join tickets t
    on t.cliente_id_limpio = a.cliente_id_limpio
left join otras o
    on o.cliente_id_limpio = a.cliente_id_limpio
-- La etiqueta sale de donde se define, como en ventas_rfm, y no de dim_cliente.
left join {{ ref('mayoristas_v3_resumen') }} c
    on c.cliente_id_limpio = a.cliente_id_limpio
