{% macro normalizar_desde_log(log_col, min_log_col, max_log_col) %}
{#
    Paso final de _normalizar_logaritmica_0_100(): min-max sobre valores
    YA logaritmizados (log_col) y sus min/max YA calculados por ambito
    (min_log_col/max_log_col, columnas planas -- no funciones de ventana
    en vivo). SQL Server no permite anidar OVER() dentro de otro OVER(),
    por eso el cálculo se separa en etapas en el modelo que llama a esto
    (ver int_top300_kpis.sql): 1) MIN(valor) OVER(ambito), 2) LOG(1 +
    valor - min) como columna plana, 3) MIN/MAX(log) OVER(ambito), y
    recién acá el paso final, aritmética pura sobre columnas ya
    materializadas.
#}
    case
        when {{ max_log_col }} = {{ min_log_col }} then 100.0
        else ({{ log_col }} - {{ min_log_col }}) * 100.0 / ({{ max_log_col }} - {{ min_log_col }})
    end
{% endmacro %}
