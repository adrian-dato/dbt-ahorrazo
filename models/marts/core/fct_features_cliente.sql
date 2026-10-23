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
-- GRUPOS DE FEATURES:
--   - categoria_3: en qué categorías compra el cliente. Se identifica por la
--     clave de dim_categoria, no por el nombre: 'sin asignar' aparece bajo 112
--     padres distintos. feature_nombre es la ruta legible, que es única.
--   - medio_pago: con qué paga (reemplaza al canal, area, de McDonald's, que
--     Ahorrazo no tiene).
-- La franja horaria quedó afuera hasta resolver de dónde sale la hora:
-- fecha_venta viene sin hora y fecha_detalle no pasa por staging.
--
-- LA MEDIDA ES POR TICKETS, en los dos grupos: participacion es la parte de
-- los tickets del cliente que incluyen la feature. Es la definición de "Share
-- Tickets" de la segmentación anterior (dbo.variables_kmeans): tickets con la
-- categoría sobre tickets totales del cliente. Por eso no suma 1 dentro de un
-- cliente: un ticket con tres categorías cuenta en las tres. En medio_pago
-- suma casi 1, salvo los tickets pagados con más de un medio. Mide hábito de
-- compra y no gasto, así que una categoría barata que el cliente lleva siempre
-- pesa tanto como una cara.
--
-- medida es la cantidad de tickets con la feature, y tickets_cliente el total
-- de tickets del cliente en la ventana.
--
-- Ventana: la de int_ventas_12m_tabla, 12 meses cerrados. fecha_corte la deja
-- explícita en la tabla.

{{ config(materialized='table') }}

with ventas as (
    select
        v.cliente_id_limpio,
        v.ticket_id,
        v.medio_pago,
        p.categoria_key_n3
    from {{ ref('int_ventas_12m_tabla') }} v
    inner join {{ ref('int_productos_limpio') }} p
        on cast(p.producto_id as varchar(100)) = cast(v.producto_id as varchar(100))
),

tickets_cliente as (
    select cliente_id_limpio, count(distinct ticket_id) as tickets_cliente
    from ventas
    group by cliente_id_limpio
),

por_categoria as (
    select
        cliente_id_limpio,
        cast('categoria_3' as varchar(20))                                       as grupo,
        -- collate explícito en las dos ramas del union: vienen de tablas
        -- distintas y SQL Server no une textos de collation distinta (error 446)
        cast(categoria_key_n3 as nvarchar(255)) collate database_default         as feature_key,
        count(distinct ticket_id)                                                as medida
    from ventas
    group by cliente_id_limpio, categoria_key_n3
),

por_medio_pago as (
    select
        cliente_id_limpio,
        cast('medio_pago' as varchar(20))                                        as grupo,
        cast(coalesce(medio_pago, '(sin dato)') as nvarchar(255)) collate database_default as feature_key,
        count(distinct ticket_id)                                                as medida
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
    cast(coalesce(c.ruta, f.feature_key) as nvarchar(500))           as feature_nombre,
    f.medida,
    t.tickets_cliente,
    cast(1.0 * f.medida / t.tickets_cliente as decimal(9, 8))        as participacion,
    {{ fecha_corte_mes_cerrado() }}                                   as fecha_corte
from features f
inner join tickets_cliente t
    on t.cliente_id_limpio = f.cliente_id_limpio
left join {{ ref('dim_categoria') }} c
    on f.grupo = 'categoria_3'
   and c.nivel = 3
   and c.categoria_key collate database_default = f.feature_key
