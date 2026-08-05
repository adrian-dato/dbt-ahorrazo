{% macro normalizar_log_0_100(columna, particion) %}
{#
    Puerto de _normalizar_logaritmica_0_100() (top_300_productos.ipynb):
    desplaza la serie para que el mínimo sea 0, aplica log1p (log(1+x)),
    y normaliza el resultado a [0,100] con min-max -- dentro de la
    partición indicada (ambito: 'GLOBAL' o pdv_id, ver int_top300_kpis).
    Si todos los valores dan igual tras el log (serie constante), 100
    para todos -- mismo comportamiento que el original.
#}
    case
        when max(log(1 + {{ columna }} - min({{ columna }}) over (partition by {{ particion }}))) over (partition by {{ particion }})
           = min(log(1 + {{ columna }} - min({{ columna }}) over (partition by {{ particion }}))) over (partition by {{ particion }})
        then 100.0
        else
            (
                log(1 + {{ columna }} - min({{ columna }}) over (partition by {{ particion }}))
                - min(log(1 + {{ columna }} - min({{ columna }}) over (partition by {{ particion }}))) over (partition by {{ particion }})
            ) * 100.0
            / (
                max(log(1 + {{ columna }} - min({{ columna }}) over (partition by {{ particion }}))) over (partition by {{ particion }})
                - min(log(1 + {{ columna }} - min({{ columna }}) over (partition by {{ particion }}))) over (partition by {{ particion }})
            )
    end
{% endmacro %}
