{# Trims, collapses repeated spaces, empty string -> NULL. #}
{% macro clean_text(column) -%}
    nullif(trim(regexp_replace({{ column }}::varchar, '\\s+', ' ')), '')
{%- endmacro %}


{#
    Status written in different ways: 'CANCELLED', ' Cancelled ', 'canceled' -> 'cancelled'.
    Unknown values pass through lower-cased and are reported by the accepted_values test.
#}
{% macro normalize_status(column) -%}
    case lower({{ clean_text(column) }})
        when 'canceled' then 'cancelled'
        when 'waitlist' then 'waitlisted'
        else lower({{ clean_text(column) }})
    end
{%- endmacro %}


{#
    The sample mixes '2026-09-14 10:22:00' and '15/09/2026 09:40'. DD/MM is assumed (Spanish source).
    An unknown format becomes NULL and fails the not_null tests: never guessed silently.
#}
{% macro parse_date(column) -%}
    coalesce(
        try_to_date(trim({{ column }}::varchar), 'YYYY-MM-DD'),
        try_to_date(trim({{ column }}::varchar), 'DD/MM/YYYY')
    )
{%- endmacro %}


{% macro parse_timestamp(column) -%}
    coalesce(
        try_to_timestamp_ntz(trim({{ column }}::varchar), 'YYYY-MM-DD HH24:MI:SS'),
        try_to_timestamp_ntz(trim({{ column }}::varchar), 'DD/MM/YYYY HH24:MI')
    )
{%- endmacro %}
