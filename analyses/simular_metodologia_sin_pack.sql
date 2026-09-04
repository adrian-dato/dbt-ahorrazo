-- NOTA: la opcion que se tomo fue otra -- en vez de sacar Pack de C1 y
-- C2, se corrigio el corte de factura grande para que cuando el IQR da 0
-- se use Q3 en su lugar (ver mayoristas_v3_tickets_unidad). Esta consulta
-- queda como registro de la alternativa que se evaluo y de por que.
--
-- Cuanto cambiaria la clasificacion si Pack saliera de C1 y C2, igual que
-- Blis, Metros y Ramo. No cambia nada en la base: recalcula el puntaje
-- leyendo las mismas tablas y muestra a donde se mueve cada cliente.
--
-- Por que se plantea: en Pack, Q1 y Q3 valen los dos 1, asi que el IQR es
-- 0 y la formula Q3 + 3*IQR colapsa a Q3. El corte de "factura grande"
-- deja de ser un corte de outlier -- en Unid es 67 contra un Q3 de 19,
-- tres veces y media mas arriba -- y pasa a ser "arriba del Q3" a secas.
-- Del lado de C1 es peor: umbral_upt tambien queda en 1, el minimo
-- posible, y el 99,4% de los clientes con actividad en Pack cumplen C1
-- por ahi. Un percentil 75 tiene que dejar pasar al 25%; en Unid, KILOS y
-- LITROS deja pasar entre 25% y 28%.
--
-- Pack sigue contando en C3 pase lo que pase: C3 es en guaranies y entra
-- toda la venta, incluida la de Blis, Metros y Ramo. Sacar Pack de C1 y
-- C2 no es ignorar esa venta, es no usarla para juzgar volumen.
--
-- SQL plano contra los esquemas de dbt, se pega y se corre. No escribe
-- nada.

with c1_c2_sin_pack as (
    select
        cliente_id_limpio,
        max(c1_upt_alto)         as c1,
        max(c2_pct_grandes_alto) as c2
    from marts_mayoristas.mayoristas_v3_metricas_unidad
    where unidad_medida <> 'Pack'
    group by cliente_id_limpio
),

comparacion as (
    select
        r.cliente_id_limpio,
        r.nivel_mayorista as nivel_hoy,
        case isnull(s.c1, 0) + isnull(s.c2, 0) + r.c3_ventas_alto
            when 3 then 'Alto'
            when 2 then 'Medio'
            when 1 then 'Potencial'
            else 'Minorista'
        end as nivel_sin_pack
    from marts_mayoristas.mayoristas_v3_resumen r
    left join c1_c2_sin_pack s
        on s.cliente_id_limpio = r.cliente_id_limpio
)

-- 1. A donde se mueve cada cliente. La diagonal (nivel_hoy =
--    nivel_sin_pack) son los que no cambian.
select
    nivel_hoy,
    nivel_sin_pack,
    count(*) as clientes,
    case when nivel_hoy = nivel_sin_pack then 'sin cambio' else 'baja' end as efecto
from comparacion
group by nivel_hoy, nivel_sin_pack
order by nivel_hoy, nivel_sin_pack;


-- 2. Las dos distribuciones lado a lado.
with c1_c2_sin_pack as (
    select
        cliente_id_limpio,
        max(c1_upt_alto)         as c1,
        max(c2_pct_grandes_alto) as c2
    from marts_mayoristas.mayoristas_v3_metricas_unidad
    where unidad_medida <> 'Pack'
    group by cliente_id_limpio
),

comparacion as (
    select
        r.nivel_mayorista as nivel_hoy,
        case isnull(s.c1, 0) + isnull(s.c2, 0) + r.c3_ventas_alto
            when 3 then 'Alto'
            when 2 then 'Medio'
            when 1 then 'Potencial'
            else 'Minorista'
        end as nivel_sin_pack
    from marts_mayoristas.mayoristas_v3_resumen r
    left join c1_c2_sin_pack s
        on s.cliente_id_limpio = r.cliente_id_limpio
),

niveles as (
    select * from (values ('Alto', 1), ('Medio', 2), ('Potencial', 3), ('Minorista', 4)) as n(nivel, orden)
)

select
    n.nivel,
    sum(case when c.nivel_hoy      = n.nivel then 1 else 0 end) as clientes_hoy,
    sum(case when c.nivel_sin_pack = n.nivel then 1 else 0 end) as clientes_sin_pack,
    sum(case when c.nivel_sin_pack = n.nivel then 1 else 0 end)
      - sum(case when c.nivel_hoy  = n.nivel then 1 else 0 end) as diferencia
from niveles n
cross join comparacion c
group by n.nivel, n.orden
order by n.orden;
