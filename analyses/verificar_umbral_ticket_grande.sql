-- Muestra Q1 y Q3 de unidades por ticket, que hoy no estan en ninguna
-- tabla -- mayoristas_v3_umbrales guarda solo el resultado
-- (umbral_ticket_grande = Q3 + 3*(Q3-Q1)), no los dos numeros de los que
-- sale. Sin ellos no hay forma de que nadie corrobore el corte con otra
-- herramienta, que es justamente lo que pidieron.
--
-- SQL plano a proposito, contra los esquemas de dbt: se pega y se corre
-- tal cual, sin `dbt compile`. Las otras analyses usan ref() porque son
-- comparaciones entre modelos; esta es una verificacion puntual que
-- alguien va a querer correr en el momento.
--
-- El corte es Q3 + 3*IQR, con una excepcion: cuando Q1 y Q3 son iguales
-- el IQR da 0 y en su lugar se usa Q3, para que la formula no colapse a
-- Q3 a secas. Es el caso de Pack, donde el corte queda en 4 (1 + 3*1) y
-- no en 1. Esta consulta recalcula con esa misma regla -- si se recalcula
-- sin ella, Pack da 1 y parece que el modelo esta mal.
--
-- Los cuartiles se recalculan desde mayoristas_v3_tickets_unidad, que es
-- exactamente la misma poblacion sobre la que se calcularon la primera
-- vez: esa tabla sale de int_mayoristas_v3_tickets_por_unidad con un
-- inner join a una tabla de 4 filas por unidad_medida, o sea que no
-- pierde ni agrega ninguna. Entonces umbral_recalculado tiene que dar
-- identico a umbral_guardado. Si no da, el problema esta adentro de dbt
-- y no en la herramienta con la que se compara.
--
-- Las 4 unidades van en ramas separadas con UNION ALL, no con
-- PARTITION BY unidad_medida. No es manía: Unid y KILOS son mas del 99%
-- de los tickets, y particionar la ventana por una columna tan despareja
-- deja dos o tres threads cargando casi todo mientras el resto queda
-- ocioso -- eso ya tumbo la instancia dos veces.


-- 1. Q1, Q3, IQR y el corte, contra el que quedo guardado.
with cuartiles as (
    select distinct
        'Unid' as unidad_medida,
        count(*) over ()                                                    as tickets,
        percentile_cont(0.25) within group (order by unidades) over ()      as q1,
        percentile_cont(0.75) within group (order by unidades) over ()      as q3
    from marts_mayoristas.mayoristas_v3_tickets_unidad
    where unidad_medida = 'Unid'

    union all

    select distinct
        'KILOS',
        count(*) over (),
        percentile_cont(0.25) within group (order by unidades) over (),
        percentile_cont(0.75) within group (order by unidades) over ()
    from marts_mayoristas.mayoristas_v3_tickets_unidad
    where unidad_medida = 'KILOS'

    union all

    select distinct
        'LITROS',
        count(*) over (),
        percentile_cont(0.25) within group (order by unidades) over (),
        percentile_cont(0.75) within group (order by unidades) over ()
    from marts_mayoristas.mayoristas_v3_tickets_unidad
    where unidad_medida = 'LITROS'

    union all

    select distinct
        'Pack',
        count(*) over (),
        percentile_cont(0.25) within group (order by unidades) over (),
        percentile_cont(0.75) within group (order by unidades) over ()
    from marts_mayoristas.mayoristas_v3_tickets_unidad
    where unidad_medida = 'Pack'
)
select
    c.unidad_medida,
    c.tickets,
    c.q1,
    c.q3,
    c.q3 - c.q1                                                as iqr,
    case when c.q3 - c.q1 <= 0 then c.q3 else c.q3 - c.q1 end   as iqr_aplicado,
    c.q3 + 3 * case when c.q3 - c.q1 <= 0 then c.q3 else c.q3 - c.q1 end as umbral_recalculado,
    u.umbral_ticket_grande                                     as umbral_guardado,
    case
        when abs(c.q3 + 3 * case when c.q3 - c.q1 <= 0 then c.q3 else c.q3 - c.q1 end
                 - u.umbral_ticket_grande) < 0.000001
            then 'coincide'
        else 'NO COINCIDE -- revisar antes de seguir'
    end as chequeo
from cuartiles c
inner join marts_mayoristas.mayoristas_v3_umbrales u
    on u.unidad_medida = c.unidad_medida
order by c.unidad_medida;


-- 2. Que pide C2 en cada unidad. El 0,40 no es el corte, es el piso: el
--    modelo usa el mayor entre el percentil 75 entre clientes y 0,40.
--    Donde el percentil da menos, C2 es literalmente "4 de cada 10". Donde
--    da mas, C2 pide mas que eso, y la regla contada como "4 de cada 10"
--    queda corta.
select
    unidad_medida,
    umbral_pct,
    case
        when umbral_pct > 0.40
            then 'manda el percentil 75: pide mas que 4 de cada 10'
        else 'manda el piso: 4 de cada 10 alcanza'
    end as que_pide_c2,
    umbral_upt,
    umbral_ticket_grande
from marts_mayoristas.mayoristas_v3_umbrales
order by unidad_medida;


-- 3. Cuanto aporta cada unidad de medida a C1 y a C2. La sospecha es
--    Pack: si su Q1 y su Q3 valen los dos 1, el IQR es 0, el umbral de
--    factura grande queda en 1 y umbral_upt tambien -- o sea que
--    cualquier cliente con actividad en Pack cumple C1 por Pack, y le
--    alcanza con que 4 de cada 10 de sus facturas de Pack lleven 2 packs
--    para cumplir C2. Esa es exactamente la condicion por la que Blis,
--    Metros y Ramo quedaron afuera de la metodologia.
--
--    pct_clientes_que_cumplen_c1 cerca de 1 en alguna unidad significa
--    que esa unidad no separa nada: le da el criterio a todo el mundo.
--    La columna "solo por esta unidad" es la que importa para decidir --
--    son los clientes que perderian el criterio si la unidad se sacara.
with por_cliente as (
    select
        cliente_id_limpio,
        sum(c1_upt_alto)         as unidades_con_c1,
        sum(c2_pct_grandes_alto) as unidades_con_c2
    from marts_mayoristas.mayoristas_v3_metricas_unidad
    group by cliente_id_limpio
)
select
    m.unidad_medida,
    count(*)                                    as clientes_con_actividad,
    sum(m.c1_upt_alto)                          as cumplen_c1_aca,
    cast(sum(m.c1_upt_alto) as float) / count(*) as pct_clientes_que_cumplen_c1,
    sum(case when m.c1_upt_alto = 1 and p.unidades_con_c1 = 1 then 1 else 0 end) as c1_solo_por_esta_unidad,
    sum(m.c2_pct_grandes_alto)                  as cumplen_c2_aca,
    cast(sum(m.c2_pct_grandes_alto) as float) / count(*) as pct_clientes_que_cumplen_c2,
    sum(case when m.c2_pct_grandes_alto = 1 and p.unidades_con_c2 = 1 then 1 else 0 end) as c2_solo_por_esta_unidad
from marts_mayoristas.mayoristas_v3_metricas_unidad m
inner join por_cliente p
    on p.cliente_id_limpio = m.cliente_id_limpio
group by m.unidad_medida
order by m.unidad_medida;
