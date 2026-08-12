{#
  Diferencia en meses entre 2 "periodos" YYYYMM (enteros, ej. 202603),
  más reciente menos más antiguo. Mismo criterio que diff_meses() en
  canibalizacion_v3.py -- reutilizado acá para no reimplementar la
  aritmética de años/meses en cada lugar que lo necesita.
#}
{% macro meses_entre_periodos(periodo_reciente, periodo_antiguo) %}
    ((({{ periodo_reciente }} / 100) * 12 + ({{ periodo_reciente }} % 100))
   - (({{ periodo_antiguo }} / 100) * 12 + ({{ periodo_antiguo }} % 100)))
{% endmacro %}
