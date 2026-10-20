-- SCD2 sobre la clasificación de Mayoristas: guarda cómo cambia el nivel de
-- cada cliente mes a mes. mayoristas_v3_resumen se recalcula entera en cada
-- corrida y no guarda nada, así que sin esto no se puede responder cuántos
-- clientes había en cada nivel en un mes pasado, ni cuándo un cliente pasó de
-- Minoristas a Mayoristas.
--
-- QUÉ SE COMPARA. strategy='check' sobre nivel_mayorista y segmento_mayorista.
-- Las medidas (venta promedio por factura, ventas totales) no entran: cambian
-- todos los meses para casi todos los clientes y generarían una versión nueva
-- por cliente por mes, sin que el nivel se haya movido. puntaje se guarda pero
-- no se compara, porque define el nivel y no puede cambiar sola.
--
-- fecha_corte es el primer día del mes en que se calculó la clasificación, o
-- sea, el final exclusivo de la ventana de 12 meses. Se guarda en la versión
-- que abre el cambio, y dice desde qué corrida vale esa versión. dbt_valid_from
-- es la hora en que corrió el snapshot, que no es lo mismo si se corre a mano
-- un día cualquiera.
--
-- LOS CLIENTES QUE SALEN. invalidate_hard_deletes=True. Un cliente sin compras
-- en los últimos 12 meses cerrados desaparece de mayoristas_v3_resumen, y es un
-- hecho de negocio: dejó de ser cliente activo. Con False su última versión
-- quedaría abierta para siempre, diciendo que hoy es Mayoristas cuando hace un
-- año que no compra, y los conteos por mes saldrían inflados. Si vuelve a
-- comprar, se abre una versión nueva. A diferencia del snapshot de
-- Canibalización, acá la fuente no es una ventana de meses que se va corriendo:
-- que un cliente salga significa algo.
--
-- La historia empieza con la primera corrida: inserta el estado actual como
-- versión 1. Lo anterior no se puede reconstruir, porque el snapshot de la
-- versión anterior de la metodología se dio de baja. Se corre después de
-- construir Mayoristas, desde el DAG mensual. Un dbt snapshot --full-refresh
-- borra la historia acumulada y no se recupera.
--
-- Si Mayoristas se reconstruye con una fuente incompleta (la ventana sigue el
-- calendario aunque el cliente no actualice las ventas), los clientes cuyas
-- únicas compras caen fuera de lo cargado salen del resumen y este snapshot
-- cierra sus versiones. Es lo que dice la definición de la ventana, y conviene
-- tenerlo presente al leer los primeros meses de historia.

{% snapshot mayoristas_v3_resumen_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='cliente_id_limpio',
        strategy='check',
        check_cols=['nivel_mayorista', 'segmento_mayorista'],
        invalidate_hard_deletes=True,
    )
}}

select
    cliente_id_limpio,
    nivel_mayorista,
    segmento_mayorista,
    puntaje,
    {{ fecha_corte_mes_cerrado() }} as fecha_corte
from {{ ref('mayoristas_v3_resumen') }}

{% endsnapshot %}
