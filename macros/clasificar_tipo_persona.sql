{#
  Física vs. jurídica a partir de cliente_id_limpio -- estructura real
  del RUC en Paraguay (confirmado, no supuesto): personas jurídicas son
  8 dígitos que arrancan en 80000000 + dígito verificador -- "8 dígitos
  que empiezan en 8" cubre TODO ese rango, a diferencia del CASE legacy
  de view_ventas_ahorrazo_filtradas_12m (prefijos '800'/'801'/'802'
  hardcodeados, que se queda corto cada vez que la SET abre un bloque
  nuevo -- ver PENDIENTES.md). Reutilizado acá para no repetir el CASE
  en cada modelo que lo necesita -- int_clientes_limpio (dimensión) e
  int_ventas_elegibles (para tenerlo directo en la fact, sin join) lo
  usan los 2 -- misma regla, no 2 versiones que puedan desalinearse.
#}
{% macro clasificar_tipo_persona(columna_cliente_id_limpio) %}
    case
        when len({{ columna_cliente_id_limpio }}) = 8
             and left({{ columna_cliente_id_limpio }}, 1) = '8'
        then 'Juridico'
        else 'Fisico'
    end
{% endmacro %}
