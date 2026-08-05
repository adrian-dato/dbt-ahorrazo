{% macro derivar_cliente_id_limpio(cliente_id_clean) %}
{#
    A partir de un cliente_id ya limpio (limpiar_id + recortar_basura_extremos),
    deriva el cliente_id_limpio:
      1. Si hay '-' o '*', toma la parte antes del primero que aparezca
         (así colapsan, ej., "444443-2" y "444443" al mismo cliente: RUC
         vs. cédula del mismo cliente). Regla original del proceso legacy,
         sin condición sobre qué sigue después del separador.
      2. Si no hay '-' ni '*', pero el id termina en un símbolo no
         numérico seguido de UN solo dígito (ej. "3891542,1",
         "2546408_6", "881511/9"), ese símbolo también funciona como
         separador de RUC -- el dígito suelto al final es el dígito
         verificador. A diferencia de la regla 1, acá sí importa que
         sea un solo dígito: es la señal de que el símbolo actúa como
         separador y no es ruido del medio del número.
      3. Si nada de eso aplica, usa el id limpio completo.

    Si el resultado de 1-3 es cadena vacía, el cliente_id_limpio final es
    NULL -- no cae de vuelta al id original. Un id que no deja ningún
    dígito utilizable (ej. el cliente_id original era un nombre de
    persona en vez de un documento -- "ABRAHAM", "SIN NOMBRE") es un
    cliente no identificable: decisión de negocio es excluirlo de la
    segmentación, no inventarle un cliente_id_limpio igual a su nombre
    (eso mezclaría a distintos clientes que comparten el mismo nombre
    placeholder). Ver int_clientes_mapeo_limpio / int_clientes_limpio
    para el filtro que aplica esta exclusión.
#}
    nullif(
        case
            when charindex(N'-', {{ cliente_id_clean }}) > 0
                then left({{ cliente_id_clean }}, charindex(N'-', {{ cliente_id_clean }}) - 1)
            when charindex(N'*', {{ cliente_id_clean }}) > 0
                then left({{ cliente_id_clean }}, charindex(N'*', {{ cliente_id_clean }}) - 1)
            when len({{ cliente_id_clean }}) >= 2
                 and right({{ cliente_id_clean }}, 2) like N'[^0-9][0-9]'
                then left({{ cliente_id_clean }}, len({{ cliente_id_clean }}) - 2)
            else {{ cliente_id_clean }}
        end,
        N''
    )
{% endmacro %}
