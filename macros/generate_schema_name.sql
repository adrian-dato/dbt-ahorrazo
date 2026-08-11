{#
  Override del default de dbt (que concatena target.schema + custom
  schema, ej. "dbt_dev_staging"). Acá se usa el nombre custom tal cual
  -- decisión explícita: dev y prod comparten la misma base (limitación
  del cliente), así que el prefijo de entorno no aportaba aislamiento
  real, solo ruido en los nombres. Ver PENDIENTES.md para la nota sobre
  qué implica esto para el target `prod` a futuro (Fase 6).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
