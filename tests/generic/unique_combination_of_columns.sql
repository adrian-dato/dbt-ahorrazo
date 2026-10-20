{#
    Prueba que una combinación de columnas no se repita: el grano de una tabla
    cuya clave no es una sola columna. Devuelve las combinaciones repetidas;
    el test falla si devuelve filas.

    Es la misma prueba que dbt_utils.unique_combination_of_columns. Se escribe
    acá en lugar de instalar el paquete porque dbt_utils pide correr
    `dbt deps` en el servidor, con acceso a internet, para una sola prueba.

    Respeta la opción `where` del test, que dbt aplica sobre `model`: en las
    tablas incrementales grandes conviene acotarla a los meses recientes, que
    son los que una corrida incremental puede duplicar.
#}
{% test unique_combination_of_columns(model, combination_of_columns) %}

select
    {{ combination_of_columns | join(', ') }},
    count(*) as filas
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1

{% endtest %}
