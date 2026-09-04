-- Que compra cada nivel, por categoria de producto, con el indice de
-- afinidad. Es el unico numero que faltaba para la presentacion: los del
-- reparto por nivel y los cortes ya estan medidos, este no.
--
-- El indice de afinidad compara dos proporciones. Arriba, cuanto pesa esa
-- categoria dentro del nivel. Abajo, cuanto pesa la misma categoria en
-- toda la base. 1,0 significa que el nivel compra esa categoria en la
-- misma proporcion que el resto; 2,3 significa que la compra 2,3 veces
-- mas de lo que se esperaria.
--
-- Se calcula sobre venta y sobre unidades, que no dicen lo mismo. Cuando
-- el de unidades da mas alto que el de venta, ese nivel compra barato y
-- por bulto en esa categoria -- que es el perfil mayorista.
--
-- OJO con el de unidades: sumar unidades entre productos de distinta
-- unidad de medida no significa nada, asi que esa columna solo se puede
-- leer filtrando una. Por eso la consulta 2 abre por unidad_medida y la 1
-- no trae unidades.
--
-- Las categorias que suman cero o negativo en el periodo salen con
-- indice_afinidad nulo, no con un numero. Pasa cuando las devoluciones
-- cancelan las ventas: no es un error, es que ahi no hay nada que medir.
--
-- Recorre las 62M lineas de int_ventas_12m_tabla. Tarda, pero es de una
-- sola vez. SQL plano contra los esquemas de dbt: se pega y se corre.


-- 1. Venta y clientes por nivel y categoria principal, con la afinidad.
with venta as (
    select
        r.nivel_mayorista,
        p.categoria_1,
        sum(cast(v.venta_gs as decimal(19, 4))) as venta,
        count(distinct v.cliente_id_limpio)     as clientes
    from intermediate.int_ventas_12m_tabla v
    inner join intermediate.int_productos_limpio p
        on v.producto_id = p.producto_id
    inner join marts_mayoristas.mayoristas_v3_resumen r
        on v.cliente_id_limpio = r.cliente_id_limpio
    group by r.nivel_mayorista, p.categoria_1
),

por_nivel as (
    select nivel_mayorista, sum(venta) as venta_nivel
    from venta group by nivel_mayorista
),

por_categoria as (
    select categoria_1, sum(venta) as venta_categoria
    from venta group by categoria_1
),

total as (select sum(venta) as venta_total from venta)

select
    v.nivel_mayorista,
    v.categoria_1,
    v.clientes,
    v.venta,
    v.venta / nullif(n.venta_nivel, 0)                  as pct_del_nivel,
    -- nullif en los dos denominadores: una categoria puede sumar cero en
    -- el periodo si las devoluciones cancelan las ventas, y ahi la
    -- division explota en vez de devolver nulo. El case adicional evita
    -- un indice negativo, que no significa nada.
    case
        when n.venta_nivel > 0 and c.venta_categoria > 0 and t.venta_total > 0
            then (v.venta / n.venta_nivel) / (c.venta_categoria / t.venta_total)
    end                                                 as indice_afinidad
from venta v
inner join por_nivel n      on n.nivel_mayorista = v.nivel_mayorista
inner join por_categoria c  on c.categoria_1 = v.categoria_1
cross join total t
order by v.nivel_mayorista, indice_afinidad desc;


-- 2. Lo mismo sobre unidades, dentro de una sola unidad de medida.
--    Cambiar 'KILOS' por la que se quiera mirar.
with unidades as (
    select
        r.nivel_mayorista,
        p.categoria_1,
        sum(v.unidades) as unidades
    from intermediate.int_ventas_12m_tabla v
    inner join intermediate.int_productos_limpio p
        on v.producto_id = p.producto_id
    inner join marts_mayoristas.mayoristas_v3_resumen r
        on v.cliente_id_limpio = r.cliente_id_limpio
    where p.unidad_medida = 'KILOS'
    group by r.nivel_mayorista, p.categoria_1
),

por_nivel as (
    select nivel_mayorista, sum(unidades) as unidades_nivel
    from unidades group by nivel_mayorista
),

por_categoria as (
    select categoria_1, sum(unidades) as unidades_categoria
    from unidades group by categoria_1
),

total as (select sum(unidades) as unidades_total from unidades)

select
    u.nivel_mayorista,
    u.categoria_1,
    u.unidades,
    u.unidades / nullif(n.unidades_nivel, 0)            as pct_del_nivel,
    case
        when n.unidades_nivel > 0 and c.unidades_categoria > 0 and t.unidades_total > 0
            then (u.unidades / n.unidades_nivel) / (c.unidades_categoria / t.unidades_total)
    end                                                 as indice_afinidad
from unidades u
inner join por_nivel n     on n.nivel_mayorista = u.nivel_mayorista
inner join por_categoria c on c.categoria_1 = u.categoria_1
cross join total t
order by u.nivel_mayorista, indice_afinidad desc;
