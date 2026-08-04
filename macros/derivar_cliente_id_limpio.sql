{% macro derivar_cliente_id_limpio(cliente_id_original, cliente_id_clean) %}
{#
    A partir de un cliente_id ya limpio (ver limpiar_id), toma la parte
    antes de '-' o '*' como cliente_id_limpio (así es como colapsan, por
    ejemplo, "444443-2" y "444443" al mismo cliente: RUC vs. cédula del
    mismo cliente). Si no hay '-' ni '*', usa el id limpio completo; si
    la limpieza dejó todo vacío, cae de vuelta al id original sin limpiar.
    Puerto 1:1 de la expresión COALESCE(...) de clientes_mapeo_limpio.sql.
#}
    coalesce(
        nullif(
            case
                when charindex(N'-', {{ cliente_id_clean }}) > 0
                    then left({{ cliente_id_clean }}, charindex(N'-', {{ cliente_id_clean }}) - 1)
                when charindex(N'*', {{ cliente_id_clean }}) > 0
                    then left({{ cliente_id_clean }}, charindex(N'*', {{ cliente_id_clean }}) - 1)
                else {{ cliente_id_clean }}
            end,
            N''
        ),
        nullif({{ cliente_id_clean }}, N''),
        {{ cliente_id_original }}
    )
{% endmacro %}
