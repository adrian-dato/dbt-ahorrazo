{% macro limpiar_id(columna) %}
{#
    Limpieza de un identificador (cliente_id, ci_ruc): trim, remueve
    espacios/tab/CR/LF, mayúsculas, y remueve letras A-Z -- deja solo
    dígitos y símbolos (ej. '-', '*'). Puerto 1:1 de la expresión inline
    que clientes_mapeo_limpio.sql repetía en 3 lugares distintos del
    stored proc (una vez por Clientes.cliente_id, una por Clientes.ci_ruc,
    una por Ventas_Ahorrazo.cliente_id) -- acá se define una sola vez.
#}
    replace(
        translate(
            upper(
                replace(replace(replace(replace(
                    ltrim(rtrim({{ columna }})),
                    N' ', N''), char(9), N''), char(10), N''), char(13), N'')
            ),
            N'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            replicate(N' ', 26)
        ),
        N' ', N''
    )
{% endmacro %}
