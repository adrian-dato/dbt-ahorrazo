{{ config(severity='warn') }}

-- fct_ventas_36m_pivotado abre la venta en tres columnas fijas, SL, R1 y R2.
-- Mes a mes, su suma tiene que ser igual a la venta de fct_ventas_36m en las
-- sucursales que están en el seed dim_sucursal_mapeo. Avisa de los meses donde
-- se separan más de 0,01%.
--
-- El caso que más importa es una sucursal nueva: si se agrega al seed, el
-- pivotado no la incluye hasta que se le agregue su columna, y su venta
-- desaparece de Canibalización sin ningún error. Acá se ve como una
-- diferencia en los meses en que esa sucursal vendió.

with pivotado as (
    select
        anio,
        mes,
        sum(SL + R1 + R2) as venta_pivotado
    from {{ ref('fct_ventas_36m_pivotado') }}
    group by anio, mes
),

base as (
    select
        f.anio,
        f.mes,
        sum(f.total_ventas) as venta_base
    from {{ ref('fct_ventas_36m') }} f
    inner join {{ ref('dim_sucursal_mapeo') }} s
        on f.pdv_id = s.pdv_id
    group by f.anio, f.mes
)

select
    p.anio,
    p.mes,
    p.venta_pivotado,
    b.venta_base,
    p.venta_pivotado - b.venta_base as diferencia
from pivotado p
inner join base b
    on p.anio = b.anio
   and p.mes  = b.mes
where abs(p.venta_pivotado - b.venta_base) > 0.0001 * abs(b.venta_base)
