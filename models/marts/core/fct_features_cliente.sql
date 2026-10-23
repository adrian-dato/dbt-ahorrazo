-- Feature store de clientes: una fila por cliente × feature, en formato largo.
-- Es la entrada de la segmentación cualitativa (cluster.py, repo
-- customer-profiling), el análogo de los pivots que McDonald's arma sobre
-- view_ventas_sar.
--
-- POR QUÉ LARGO Y NO ANCHO. categoria_3 tiene 999 categorías con venta en la
-- ventana, y una tabla con una columna por categoría más los medios de pago
-- pasa el límite de 1.024 columnas de SQL Server. Además la matriz es casi
-- toda ceros: un cliente típico compra en 19 categorías. Acá se guardan todas
-- las features; la tabla ancha que lee el clustering se arma después, con las
-- que se elijan.
--
-- GRUPOS DE FEATURES, mismo criterio que McDonald's:
--   - categoria_3: participación de cada categoría en el gasto del cliente
--     (McDonald's usa clasificacion_2 por monto). Se identifica por la clave
--     de dim_categoria, no por el nombre: 'sin asignar' aparece bajo 112
--     padres distintos. feature_nombre es la ruta legible, que es única.
--   - medio_pago: participación de cada medio en los tickets del cliente
--     (reemplaza al canal, area, que Ahorrazo no tiene).
-- La franja horaria quedó afuera hasta resolver de dónde sale la hora:
-- fecha_venta viene sin hora y fecha_detalle no pasa por staging.
--
-- participacion suma 1 dentro de cada cliente y grupo. medida guarda el valor
-- sin normalizar (guaraníes o tickets) por si otro uso pide otra
-- normalización. En categoria_3 entran solo las categorías con gasto neto
-- positivo: una categoría donde el cliente devolvió más de lo que compró daría
-- una participación negativa.
--
-- Ventana: la de int_ventas_12m_tabla, 12 meses cerrados. fecha_corte la deja
-- explícita en la tabla.

{{ config(materialized='table') }}

with ventas as (
    select
        v.cliente_id_limpio,
        v.ticket_id,
        v.venta_gs,
        v.medio_pago,
        p.categoria_key_n3
    from {{ ref('int_ventas_12m_tabla') }} v
    inner join {{ ref('int_productos_limpio') }} p
        on cast(p.producto_id as varchar(100)) = cast(v.producto_id as varchar(100))
),

por_categoria as (
    select
        cliente_id_limpio,
        cast('categoria_3' as varchar(20))           as grupo,
        -- collate explícito en las dos ramas del union: vienen de tablas
        -- distintas y SQL Server no une textos de collation distinta (error 446)
        cast(categoria_key_n3 as nvarchar(255)) collate database_default as feature_key,
        cast(sum(venta_gs) as decimal(19, 2))         as medida
    from ventas
    group by cliente_id_limpio, categoria_key_n3
    having sum(venta_gs) > 0
),

por_medio_pago as (
    select
        cliente_id_limpio,
        cast('medio_pago' as varchar(20))                                       as grupo,
        cast(coalesce(medio_pago, '(sin dato)') as nvarchar(255)) collate database_default as feature_key,
        cast(count(distinct ticket_id) as decimal(19, 2))                       as medida
    from ventas
    group by cliente_id_limpio, coalesce(medio_pago, '(sin dato)')
),

features as (
    select * from por_categoria
    union all
    select * from por_medio_pago
)

select
    f.cliente_id_limpio,
    f.grupo,
    f.feature_key,
    cast(coalesce(c.ruta, f.feature_key) as nvarchar(500))  as feature_nombre,
    f.medida,
    cast(f.medida / sum(f.medida) over (partition by f.cliente_id_limpio, f.grupo)
         as decimal(9, 8))                                   as participacion,
    {{ fecha_corte_mes_cerrado() }}                          as fecha_corte
from features f
left join {{ ref('dim_categoria') }} c
    on f.grupo = 'categoria_3'
   and c.nivel = 3
   and c.categoria_key collate database_default = f.feature_key
