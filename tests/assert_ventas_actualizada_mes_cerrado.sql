{{ config(severity='warn') }}

-- Alerta de frescura de Ventas_Ahorrazo -- reemplaza el chequeo viejo
-- de "dbt source freshness" (umbral relativo, hace N días) por uno de
-- calendario: los 3 marts del portfolio asumen meses cerrados completos
-- (macro fecha_corte_mes_cerrado()), así que lo que importa no es cuán
-- reciente es la última fila, sino si el mes cerrado más reciente ya
-- terminó de cargar.
--
-- severity='warn' a propósito: esto NO debe fallar el DAG -- una falla
-- de DAG tiene que significar una falla real (ej. de conexión), no esta
-- alerta. El task que corre esto (orquestacion_ahorrazo/scripts/
-- dbt_ahorrazo/check_freshness.py) lee el resultado en run_results.json
-- y manda su propio mail si este test warnea, sin marcar el task como
-- failed.

select 1 as ventas_desactualizada
where (
    select max(fecha_venta)
    from {{ source('dato_solutions', 'Ventas_Ahorrazo') }}
) < dateadd(day, -1, {{ fecha_corte_mes_cerrado() }})
