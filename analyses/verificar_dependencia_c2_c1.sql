-- Verifica si C2 puede cumplirse sin C1 -- el punto 4 de los pendientes
-- del tablero. Si no puede, el puntaje no son tres marcas independientes
-- sino una escalera (volumen -> repeticion) con el valor por visita en
-- paralelo. No cambia ningun numero: cambia como conviene contarlo en la
-- pagina de metodologia y en el panel de "que le falta para subir".
--
-- No es un modelo, y son tres consultas: compilar con
-- `dbt compile --select verificar_dependencia_c2_c1` y correr el SQL
-- resultante a mano. `dbt show` no sirve aca -- devuelve una sola grilla.
--
-- El argumento algebraico. upt es avg(unidades) sobre los tickets del
-- cliente en esa unidad, y pct_tickets_grandes es la fraccion de esos
-- tickets con unidades > umbral_ticket_grande. Si una fraccion p de los
-- tickets supera U, la suma de unidades ya vale por lo menos p*n*U, asi
-- que upt >= p*U. C2 exige p >= umbral_pct, entonces todo cliente que
-- cumple C2 tiene upt >= umbral_pct * umbral_ticket_grande. Donde ese
-- piso llega a umbral_upt, cumplir C2 obliga a cumplir C1.
--
-- Ojo con el piso: el multiplicador es umbral_pct, no 0.40. El 0.40 es
-- el minimo que mayoristas_v3_metricas_unidad le aplica al percentil 75
-- (`case when q3_pct > 0.40 then q3_pct else 0.40`), asi que la columna
-- umbral_pct ya viene con ese piso adentro. Usar 0.40 directo subestima
-- el corte en cualquier unidad donde el percentil real haya quedado mas
-- alto, y puede dar "pueden darse por separado" donde en realidad no.
--
-- La implicacion sube sola al nivel de cliente: mayoristas_v3_resumen
-- arma C1 y C2 con max() sobre las unidades, o sea "cumple en cualquiera
-- de las cuatro". Si en cada unidad C2 implica C1, entonces un cliente
-- que dispara C2 en alguna unidad dispara C1 en esa misma unidad, y por
-- lo tanto C1 global.
--
-- Que esperar: la consulta 1 dice si la implicacion vale por unidad y
-- por que. La 2 la confirma contra los datos -- la columna
-- c1_no_c2_si tiene que dar 0 en toda unidad donde la 1 diga "C2 implica
-- C1". Si no da 0, el que esta mal es el razonamiento, no la base:
-- revisar antes de escribir nada en la pagina de metodologia. La 3 es la
-- tabla completa de combinaciones a nivel cliente, que ademas sirve para
-- el panel de "que le falta para subir" del ranking.


-- 1. Los cortes, y si el piso de upt que garantiza C2 alcanza para C1.
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


-- 2. Lo mismo contra los datos: las cuatro combinaciones por unidad.
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


-- 3. Las ocho combinaciones a nivel cliente, ya con el nivel resultante.
select
    c1_upt_alto,
    c2_pct_grandes_alto,
    c3_ventas_alto,
    nivel_mayorista,
    count(*) as clientes
from {{ ref('mayoristas_v3_resumen') }}
group by c1_upt_alto, c2_pct_grandes_alto, c3_ventas_alto, nivel_mayorista
order by c1_upt_alto, c2_pct_grandes_alto, c3_ventas_alto;
