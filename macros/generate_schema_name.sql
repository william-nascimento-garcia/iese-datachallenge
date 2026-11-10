{#
    PRE / PRO: exact schema names (GESTOR_EVENTOS in Silver, EVENTS in Gold).
    DEV: prefixed with the developer's target schema (e.g. WILLIAM_GESTOR_EVENTOS), so developers
    sharing DEV_SILVER_DTP never overwrite each other's tables.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set base = (custom_schema_name or target.schema) | trim | upper -%}
    {%- if target.name in ['pre', 'pro'] -%}
        {{ base }}
    {%- else -%}
        {{ target.schema | upper }}_{{ base }}
    {%- endif -%}
{%- endmacro %}
