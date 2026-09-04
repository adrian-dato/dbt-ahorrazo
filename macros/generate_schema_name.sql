{#
  Override del default de dbt (que concatena target.schema + custom
  schema, ej. "dbt_dev_staging"). Acá se usa el nombre custom tal cual
  -- decisión explícita: dev y prod comparten la misma base (limitación
  del cliente), así que el prefijo de entorno no aportaba aislamiento
  real, solo ruido en los nombres. Si algún día dev y prod pasan a bases
  distintas, esta macro es el único lugar donde hay que tocar.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
