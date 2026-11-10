{#
    attendee_key: keyed SHA-256 of the normalised email, computed by a SECURE function
    (security/V1.0__pii_masking.sql). The key lives in the function body, which callers cannot read.
    A plain sha2(email) is not enough: emails are guessable, so it could be reversed with a list.
#}
{% macro pseudonymize(expression) -%}
    {{ target.name | upper }}_FW_METADATA_DTP.GOVERNANCE.PSEUDONYMIZE({{ expression }})
{%- endmacro %}


{#
    Post-hook: sets the PII tag on every column declared with `config: {meta: {pii: ...}}` in the .yml.
    The masking policy is attached to the tag, so tagging is all a model needs to be protected.
    Re-applied on every run because `create or replace` (full refresh) drops column tags.
#}
{% macro apply_pii_tags() -%}
    {%- if execute and model.columns -%}
        {%- set statements = [] -%}
        {%- for column_name, column in model.columns.items() -%}
            {%- set pii = (column.meta or {}).get('pii') or ((column.config or {}).get('meta') or {}).get('pii') -%}
            {%- if pii -%}
                {%- do statements.append(
                    "alter table " ~ this ~ " modify column " ~ column_name
                    ~ " set tag " ~ target.name | upper ~ "_FW_METADATA_DTP.GOVERNANCE.PII = '" ~ pii ~ "'"
                ) -%}
            {%- endif -%}
        {%- endfor -%}
        {{ statements | join(';\n') }}
    {%- endif -%}
{%- endmacro %}
