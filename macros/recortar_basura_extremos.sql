{% macro recortar_basura_extremos(expr) %}
{#
    Saca símbolos sueltos al principio y al final de un id ya pasado por
    limpiar_id (ej. "|1700599-0" -> "1700599-0", "3253286|" -> "3253286").
    No toca lo que hay en el medio (eso lo resuelve derivar_cliente_id_limpio).
    Si no queda ningún dígito en absoluto, el resultado es cadena vacía
    (ids que son puro texto -- ver derivar_cliente_id_limpio para qué pasa
    con esos: no se les asigna ningún cliente_id_limpio).

    Encontrado con datos reales: el proceso legacy prometía en un
    comentario "quita el caracter '|'" pero el código nunca lo hacía --
    esto lo resuelve de forma general (cualquier símbolo en los extremos),
    no solo el caso puntual del '|'.
#}
    case
        when patindex('%[0-9]%', ({{ expr }})) = 0 then N''
        else
            substring(
                left(
                    ({{ expr }}),
                    len(({{ expr }})) - patindex('%[0-9]%', reverse(({{ expr }}))) + 1
                ),
                patindex('%[0-9]%', ({{ expr }})),
                len(({{ expr }}))
            )
    end
{% endmacro %}
