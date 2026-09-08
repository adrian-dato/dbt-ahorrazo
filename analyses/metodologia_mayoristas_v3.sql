-- Referencia completa de la metodologia v3 de Clientes Mayoristas: todas las
-- consultas de diagnostico que se corrieron para armar y remedir
-- prompt_presentacion_mayoristas.txt (en la raiz del workspace), en un solo
-- archivo en vez de repartidas en cinco. Reemplaza a:
--   verificar_umbral_ticket_grande.sql
--   verificar_dependencia_c2_c1.sql
--   perfil_por_categoria.sql
--   que_queda_fuera_del_analisis.sql
--   pendientes_presentacion_mayoristas.sql
-- Esos cinco archivos se borraron -- este es el unico que queda.
--
-- No es un modelo: no construye nada, no lo lee ningun DAG ni ningun otro
-- modelo. Son 17 consultas de solo lectura, en 5 secciones, para reproducir
-- o auditar cualquier numero de la presentacion o del tablero.
--
-- Como correrlo: dbt compile las resuelve todas de una, pero varias
-- secciones tienen mas de un `select` separado por `;`, y ahi `dbt show`
-- devuelve una sola grilla. La forma que funciona siempre:
--
--     dbt compile --select metodologia_mayoristas_v3
--
-- y correr a mano el archivo que queda en
-- target/compiled/dbt_ahorrazo/analyses/metodologia_mayoristas_v3.sql,
-- consulta por consulta. Las secciones 1 y 3 usan ref() porque comparan
-- contra los modelos por nombre; las secciones 2, 4 y 5 son SQL plano
-- contra los esquemas de dbt a proposito, para que se puedan pegar y correr
-- sin pasar por dbt compile si hace falta algo rapido.
--
-- Cuando cambie algo que toque estos numeros (el corte de Pack, la ventana
-- de 12 meses, una unidad de medida nueva), correr esto de nuevo y
-- actualizar prompt_presentacion_mayoristas.txt a mano con lo que salga --
-- este archivo no escribe a ningun lado.


-- =====================================================================
-- SECCION 1 -- QUE QUEDA FUERA DEL ANALISIS, Y POR QUE
-- =====================================================================
-- Cuanto de la venta de la cadena entra al analisis de Mayoristas y cuanto
-- queda afuera, con el motivo de cada exclusion. Es el numero que abre la
-- presentacion (doc, seccion 3.5): sin el, la primera pregunta de
-- cualquiera que mire los resultados -- "esto es sobre todo, o sobre una
-- parte?" -- se contesta con un "creo que".
--
-- Las exclusiones no son un descarte de datos malos: son decisiones de
-- negocio sobre que es una venta relevante para clasificar clientes. Una
-- bolsa de supermercado no dice nada sobre si alguien revende, y un
-- servicio tampoco.
--
-- SIN `declare`. Las variables de T-SQL viven solo dentro de su lote, y
-- casi todos los clientes de SQL mandan cada statement en un lote propio:
-- la consulta terminaba filtrando `between null and null` y devolviendo
-- cero filas sin avisar. La ventana entra como CTE y se resuelve dentro de
-- la misma consulta.
--
-- La ventana se toma de int_ventas_12m_tabla en vez de recalcularla, asi
-- la comparacion es contra exactamente el mismo periodo que se analizo y
-- no se duplica la regla de "12 meses cerrados".
--
-- Recorre la fact completa (55M+ filas). Tarda. SQL plano contra los
-- esquemas de dbt.

-- 1.1. Que periodo se esta comparando.
select min(fecha_venta) as ventana_desde, max(fecha_venta) as ventana_hasta
from intermediate.int_ventas_12m_tabla;


-- 1.2. El reparto: cada linea de venta del periodo, con el motivo por el
--    que entro o no al analisis. El orden de los CASE importa -- una
--    linea puede cumplir dos motivos y se cuenta en el primero.
with ventana as (
    select min(fecha_venta) as desde, max(fecha_venta) as hasta
    from intermediate.int_ventas_12m_tabla
),

clasificado as (
    select
        case
            when p.producto_id is null                        then '1 - producto sin ficha en el catalogo'
            when p.id_empresa <> 3                            then '2 - producto de otra empresa del grupo'
            when isnull(p.categoria_2, '') like '%bolsa%'      then '3 - bolsas de supermercado'
            when isnull(p.categoria_1, '') like '%egre%'       then '4 - egresos, no es venta a cliente'
            when isnull(p.categoria_1, '') like '%servi%'      then '5 - servicios'
            when isnull(p.categoria_1, '') like '%activo%'     then '6 - activos de la empresa'
            when isnull(p.categoria_1, '') like '%insumos%'    then '7 - insumos internos'
            when pe.producto_id is not null                   then '8 - producto excluido a mano'
            when isnull(c.cliente_id_limpio, '') = '44444401' then '9 - cliente de prueba'
            else                                                   '0 - ENTRA AL ANALISIS'
        end                as motivo,
        v.venta_gs         as venta_gs,
        c.cliente_id_limpio as cliente_id_limpio
    from staging.stg_ventas v
    cross join ventana w
    left join staging.stg_clientes_mapeo c
        on v.cliente_id = c.cliente_id
    left join staging.stg_productos p
        on cast(v.producto_id as varchar(100)) = cast(p.producto_id as varchar(100))
    left join seeds.productos_excluidos pe
        on cast(v.producto_id as varchar(100)) = cast(pe.producto_id as varchar(100))
    where v.fecha_venta >= w.desde
      and v.fecha_venta <= w.hasta
)

select
    motivo,
    count(*)                                   as lineas,
    sum(cast(venta_gs as decimal(19, 4)))      as venta_gs,
    count(distinct cliente_id_limpio)          as clientes
from clasificado
group by motivo
order by motivo;


-- 1.3. Cuanto pesa cada unidad de medida dentro de lo que entra.
--
--    Sin count(distinct): la version anterior contaba tickets y clientes
--    distintos sobre 55 millones de filas y pasaba de media hora. Lineas
--    y venta salen de un GROUP BY normal y alcanzan para el slide.
--
--    Blis, Metros y Ramo entran en C3, que es en guaranies, pero no en C1
--    ni en C2: casi el 100% de esas facturas lleva una sola pieza y no hay
--    corte posible que separe una compra grande de una normal.
select
    p.unidad_medida,
    case
        when p.unidad_medida in ('Unid', 'KILOS', 'LITROS', 'Pack')
            then 'entra en los tres criterios'
        else 'solo entra en C3'
    end                                      as alcance,
    count(*)                                 as lineas,
    sum(cast(v.venta_gs as decimal(19, 4)))  as venta_gs
from intermediate.int_ventas_12m_tabla v
inner join intermediate.int_productos_limpio p
    on v.producto_id = p.producto_id
group by p.unidad_medida
order by venta_gs desc;


-- 1.4. Facturas y clientes por unidad de medida, para las cuatro que
--    entran en C1 y C2. Sale de mayoristas_v3_tickets_unidad, que ya esta
--    agregada a grano factura: 8 millones de filas en vez de 55, y los
--    distintos se calculan sobre eso. OJO: esto es facturas que TOCAN esa
--    unidad, no facturas que son UNICAMENTE esa unidad (una factura mixta
--    cuenta en mas de una fila).
select
    unidad_medida,
    count(*)                            as facturas_por_unidad,
    count(distinct ticket_id)           as facturas_distintas,
    count(distinct cliente_id_limpio)   as clientes
from marts_mayoristas.mayoristas_v3_tickets_unidad
group by unidad_medida
order by facturas_por_unidad desc;


-- 1.5. Cuantos clientes quedarian sin ningun criterio de volumen medible,
--    es decir los que solo compraron en Blis, Metros o Ramo. Son clientes
--    clasificados igual -- por C3 -- pero de los que no se sabe nada sobre
--    su volumen.
select count(*) as clientes_solo_en_unidades_sin_corte
from (
    select v.cliente_id_limpio
    from intermediate.int_ventas_12m_tabla v
    inner join intermediate.int_productos_limpio p
        on v.producto_id = p.producto_id
    group by v.cliente_id_limpio
    having sum(case when p.unidad_medida in ('Unid', 'KILOS', 'LITROS', 'Pack') then 1 else 0 end) = 0
) t;


-- =====================================================================
-- SECCION 2 -- LOS UMBRALES: Q1, Q3, IQR Y EL CORTE DE FACTURA GRANDE
-- =====================================================================
-- Muestra Q1 y Q3 de unidades por ticket, que no estan en ninguna tabla --
-- mayoristas_v3_umbrales guarda solo el resultado (umbral_ticket_grande),
-- no los dos numeros de los que sale. Sin ellos no hay forma de que nadie
-- corrobore el corte con otra herramienta.
--
-- SQL plano a proposito, sin ref(): es una verificacion puntual que
-- alguien va a querer correr en el momento, sin pasar por dbt compile.
--
-- El corte es Q3 + 3*IQR cuando el IQR real (Q3 - Q1) es positivo. Cuando
-- Q1 y Q3 son iguales el IQR da 0 y en su lugar el corte es 2*Q3 directo,
-- para que no colapse a Q3 a secas. Es el caso de Pack, donde el corte
-- queda en 2 (2*1) y no en 1. La consulta 2.1 recalcula con esa misma
-- regla -- si se recalcula sin ella, Pack da 1 y parece que el modelo esta
-- mal.
--
-- Los cuartiles se recalculan desde mayoristas_v3_tickets_unidad, que es
-- exactamente la misma poblacion sobre la que se calcularon la primera
-- vez, asi que umbral_recalculado tiene que dar identico a
-- umbral_guardado. Si no da, el problema esta adentro de dbt y no en la
-- herramienta con la que se compara.
--
-- Las 4 unidades van en ramas separadas con UNION ALL, no con
-- PARTITION BY unidad_medida. No es mania: Unid y KILOS son mas del 99% de
-- los tickets, y particionar la ventana por una columna tan despareja deja
-- dos o tres threads cargando casi todo mientras el resto queda ocioso --
-- eso ya tumbo la instancia dos veces.

-- 2.1. Q1, Q3, IQR y el corte, contra el que quedo guardado.
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
    case
        when c.q3 - c.q1 <= 0 then 2 * c.q3
        else c.q3 + 3 * (c.q3 - c.q1)
    end                                                         as umbral_recalculado,
    u.umbral_ticket_grande                                     as umbral_guardado,
    case
        when abs(
                case
                    when c.q3 - c.q1 <= 0 then 2 * c.q3
                    else c.q3 + 3 * (c.q3 - c.q1)
                end - u.umbral_ticket_grande) < 0.000001
            then 'coincide'
        else 'NO COINCIDE -- revisar antes de seguir'
    end as chequeo
from cuartiles c
inner join marts_mayoristas.mayoristas_v3_umbrales u
    on u.unidad_medida = c.unidad_medida
order by c.unidad_medida;


-- 2.2. Que pide C2 en cada unidad. El 0,40 no es el corte, es el piso: el
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


-- 2.3. Cuanto aporta cada unidad de medida a C1 y a C2. La sospecha
--    original era Pack: con Q1 y Q3 iguales a 1 (antes del fix), el
--    umbral de factura grande y umbral_upt quedaban los dos en 1, y
--    practicamente cualquier cliente con actividad en Pack cumplia C1 por
--    ahi. Es la misma condicion por la que Blis, Metros y Ramo quedaron
--    afuera de la metodologia desde el principio.
--
--    pct_clientes_que_cumplen_c1 cerca de 1 en alguna unidad significa que
--    esa unidad no separa nada: le da el criterio a todo el mundo. La
--    columna "solo por esta unidad" es la que importa para decidir -- son
--    los clientes que perderian el criterio si la unidad se sacara.
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


-- =====================================================================
-- SECCION 3 -- LAS UNIDADES DE MEDIDA: SI C2 IMPLICA C1
-- =====================================================================
-- Verifica si C2 puede cumplirse sin C1. Si no puede, el puntaje no son
-- tres marcas independientes sino una escalera (volumen -> repeticion)
-- con el valor por visita en paralelo. No cambia ningun numero: cambia
-- como conviene contarlo en la pagina de metodologia y en el panel de
-- "que le falta para subir".
--
-- El argumento algebraico. upt es avg(unidades) sobre los tickets del
-- cliente en esa unidad, y pct_tickets_grandes es la fraccion de esos
-- tickets con unidades > umbral_ticket_grande. Si una fraccion p de los
-- tickets supera U, la suma de unidades ya vale por lo menos p*n*U, asi
-- que upt >= p*U. C2 exige p >= umbral_pct, entonces todo cliente que
-- cumple C2 tiene upt >= umbral_pct * umbral_ticket_grande. Donde ese piso
-- llega a umbral_upt, cumplir C2 obliga a cumplir C1.
--
-- Ojo con el piso: el multiplicador es umbral_pct, no 0.40. El 0.40 es el
-- minimo que mayoristas_v3_metricas_unidad le aplica al percentil 75
-- (`case when q3_pct > 0.40 then q3_pct else 0.40`), asi que la columna
-- umbral_pct ya viene con ese piso adentro.
--
-- Desde el fix del corte de Pack (ver seccion 2), esta garantia dejo de
-- valer por algebra para Pack especificamente: 0,4 * 2 = 0,8, por debajo
-- de umbral_upt = 1. Sigue sin aparecer ningun caso real (consulta 3.2),
-- pero ya no esta garantizado por formula -- si el mix de compras de Pack
-- cambia, esto puede dejar de cumplirse y hay que volver a correr esta
-- seccion.
--
-- Que esperar: la consulta 3.1 dice si la implicacion vale por unidad y
-- por que. La 3.2 la confirma contra los datos -- la columna c1_no_c2_si
-- tiene que dar 0 en toda unidad donde la 3.1 diga "C2 implica C1". Si no
-- da 0, el que esta mal es el razonamiento, no la base: revisar antes de
-- escribir nada en la pagina de metodologia. La 3.3 es la tabla completa
-- de combinaciones a nivel cliente, que ademas sirve para el panel de
-- "que le falta para subir" del ranking.

-- 3.1. Los cortes, y si el piso de upt que garantiza C2 alcanza para C1.
select
    unidad_medida,
    umbral_ticket_grande,
    umbral_upt,
    umbral_pct,
    umbral_pct * umbral_ticket_grande as piso_upt_de_quien_cumple_c2,
    case
        when umbral_pct * umbral_ticket_grande >= umbral_upt
            then 'C2 implica C1'
        else 'pueden darse por separado'
    end as veredicto
from {{ ref('mayoristas_v3_umbrales') }}
order by unidad_medida;


-- 3.2. Lo mismo contra los datos: las cuatro combinaciones por unidad.
select
    unidad_medida,
    count(*) as clientes_con_actividad,
    sum(case when c1_upt_alto = 0 and c2_pct_grandes_alto = 1 then 1 else 0 end) as c1_no_c2_si,
    sum(case when c1_upt_alto = 1 and c2_pct_grandes_alto = 0 then 1 else 0 end) as c1_si_c2_no,
    sum(case when c1_upt_alto = 1 and c2_pct_grandes_alto = 1 then 1 else 0 end) as ambos,
    sum(case when c1_upt_alto = 0 and c2_pct_grandes_alto = 0 then 1 else 0 end) as ninguno
from {{ ref('mayoristas_v3_metricas_unidad') }}
group by unidad_medida
order by unidad_medida;


-- 3.3. Las ocho combinaciones a nivel cliente, ya con el nivel resultante.
select
    c1_upt_alto,
    c2_pct_grandes_alto,
    c3_ventas_alto,
    nivel_mayorista,
    count(*) as clientes
from {{ ref('mayoristas_v3_resumen') }}
group by c1_upt_alto, c2_pct_grandes_alto, c3_ventas_alto, nivel_mayorista
order by c1_upt_alto, c2_pct_grandes_alto, c3_ventas_alto;


-- =====================================================================
-- SECCION 4 -- PERFIL DE CADA NIVEL POR CATEGORIA
-- =====================================================================
-- Que compra cada nivel, por categoria de producto, con el indice de
-- afinidad. Es el dato de "que compra cada uno" de la presentacion (doc,
-- seccion 7).
--
-- El indice de afinidad compara dos proporciones. Arriba, cuanto pesa esa
-- categoria dentro del nivel. Abajo, cuanto pesa la misma categoria en
-- toda la base. 1,0 significa que el nivel compra esa categoria en la
-- misma proporcion que el resto; 2,3 significa que la compra 2,3 veces mas
-- de lo que se esperaria.
--
-- Se calcula sobre venta y sobre unidades, que no dicen lo mismo. Cuando
-- el de unidades da mas alto que el de venta, ese nivel compra barato y
-- por bulto en esa categoria -- que es el perfil mayorista.
--
-- OJO con el de unidades: sumar unidades entre productos de distinta
-- unidad de medida no significa nada, asi que esa columna solo se puede
-- leer filtrando una. Por eso la consulta 4.2 abre por unidad_medida y la
-- 4.1 no trae unidades.
--
-- Las categorias que suman cero o negativo en el periodo salen con
-- indice_afinidad nulo, no con un numero. Pasa cuando las devoluciones
-- cancelan las ventas: no es un error, es que ahi no hay nada que medir.
--
-- Recorre las 55M+ lineas de int_ventas_12m_tabla. Tarda, pero es de una
-- sola vez. SQL plano contra los esquemas de dbt.

-- 4.1. Venta y clientes por nivel y categoria principal, con la afinidad.
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


-- 4.2. Lo mismo sobre unidades, dentro de una sola unidad de medida.
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


-- =====================================================================
-- SECCION 5 -- REPARTO POR NIVEL Y NUMEROS SUELTOS DE LA PRESENTACION
-- =====================================================================
-- Lo que le faltaba a prompt_presentacion_mayoristas.txt despues del fix
-- del corte de Pack: reparto por nivel (doc, 3.1), corte de C3 (doc, 3.2),
-- facturas y clientes totales y catalogo (doc, 3.6). SQL plano contra los
-- esquemas de dbt.

-- 5.1. Reparto por nivel: clientes, venta y ticket mediano.
--    Ticket mediano = mediana de venta_gs por factura individual dentro
--    del nivel (no el promedio, que un cliente muy grande podria inflar,
--    y no la mediana de los promedios por cliente).
with venta_por_ticket as (
    select
        r.nivel_mayorista,
        v.cliente_id_limpio,
        v.ticket_id,
        sum(v.venta_gs) as venta_ticket
    from intermediate.int_ventas_12m_tabla v
    inner join marts_mayoristas.mayoristas_v3_resumen r
        on v.cliente_id_limpio = r.cliente_id_limpio
    group by r.nivel_mayorista, v.cliente_id_limpio, v.ticket_id
),

medianas as (
    select distinct
        nivel_mayorista,
        percentile_cont(0.5) within group (order by venta_ticket)
            over (partition by nivel_mayorista) as ticket_mediano
    from venta_por_ticket
),

agregado as (
    select
        nivel_mayorista,
        count(distinct cliente_id_limpio) as clientes,
        sum(venta_ticket)                 as venta
    from venta_por_ticket
    group by nivel_mayorista
)

select
    a.nivel_mayorista,
    a.clientes,
    cast(a.clientes as float) / sum(a.clientes) over () as pct_clientes,
    a.venta,
    a.venta / sum(a.venta) over ()                       as pct_venta,
    a.venta / a.clientes                                 as venta_media_cliente,
    m.ticket_mediano
from agregado a
inner join medianas m on m.nivel_mayorista = a.nivel_mayorista
order by case a.nivel_mayorista
             when 'Alto' then 1 when 'Medio' then 2
             when 'Potencial' then 3 else 4
         end;


-- 5.2. Corte de C3. Ya vive calculado en mayoristas_v3_resumen (columna
--    umbral_c3, repetida en cada fila) -- no hace falta recalcularlo.
select distinct umbral_c3
from marts_mayoristas.mayoristas_v3_resumen;


-- 5.3. Facturas totales del periodo: grano cliente_id_limpio x ticket_id
--    sobre TODA la venta elegible (no solo las 4 unidades con volumen, a
--    diferencia de mayoristas_v3_tickets_unidad -- por eso este numero no
--    tiene por que coincidir con la suma de la consulta 1.4).
select count(*) as facturas_totales
from (
    select cliente_id_limpio, ticket_id
    from intermediate.int_ventas_12m_tabla
    group by cliente_id_limpio, ticket_id
) t;


-- 5.4. Clientes totales del periodo: TODOS los que compraron algo en la
--    ventana, sin aplicar ninguna exclusion (ni de producto ni de cliente
--    de prueba) -- el numero amplio que usan las secciones 0bis/1/3.6 del
--    doc. Es mas chico que lo que decia la presentacion original
--    (398.433): la hipotesis sin confirmar es que ese numero contaba
--    cliente_id crudo, sin pasar por el mapeo que colapsa duplicados de
--    RUC/cedula. Para probar esa hipotesis, cambiar
--    `count(distinct c.cliente_id_limpio)` por
--    `count(distinct v.cliente_id)` abajo.
with ventana as (
    select min(fecha_venta) as desde, max(fecha_venta) as hasta
    from intermediate.int_ventas_12m_tabla
)
select count(distinct c.cliente_id_limpio) as clientes_totales_ventana
from staging.stg_ventas v
cross join ventana w
left join staging.stg_clientes_mapeo c
    on v.cliente_id = c.cliente_id
where v.fecha_venta >= w.desde
  and v.fecha_venta <= w.hasta;


-- 5.5. Catalogo: cuantos productos y categorias distintas, en los 5
--    niveles que tiene int_productos_limpio (categoria_1 .. categoria_5,
--    mas categoria_4_limpio que ya tiene el fallback aplicado).
--    categoria_1 = "categorias principales", categoria_2 = "subcategorias"
--    y categoria_4_limpio = "categorias de detalle" de la presentacion --
--    confirmado, coinciden exacto (11 / 116 / 2.616). El conteo de
--    productos (367.386) no coincide con el "40 mil" original y no se
--    encontro de donde salio ese numero viejo.
select
    count(distinct producto_id)        as productos,
    count(distinct categoria_1)        as categoria_1,
    count(distinct categoria_2)        as categoria_2,
    count(distinct categoria_3)        as categoria_3,
    count(distinct categoria_4)        as categoria_4,
    count(distinct categoria_4_limpio) as categoria_4_limpio,
    count(distinct categoria_5)        as categoria_5
from intermediate.int_productos_limpio;


-- 5.6. Facturas distintas de Blis/Metros/Ramo, para la cifra de "cuanto
--    pesa lo que entra a medias" del doc (seccion 3.5). OJO: esto cuenta
--    facturas que TOCAN Blis/Metros/Ramo, no facturas que son UNICAMENTE
--    esas tres unidades -- una factura mixta (con kilos y un ramo de
--    flores, por ejemplo) cuenta igual, asi que no es directamente
--    comparable contra el dato original de facturas puramente
--    residuales. Para esa version exacta, agregar
--    `having sum(case when p.unidad_medida not in ('Blis','Metros','Ramo') then 1 else 0 end) = 0`
--    al group by de abajo.
select count(*) as facturas_blis_metros_ramo
from (
    select v.cliente_id_limpio, v.ticket_id
    from intermediate.int_ventas_12m_tabla v
    inner join intermediate.int_productos_limpio p
        on v.producto_id = p.producto_id
    where p.unidad_medida in ('Blis', 'Metros', 'Ramo')
    group by v.cliente_id_limpio, v.ticket_id
) t;
