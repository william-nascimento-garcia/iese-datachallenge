{#
    Custom generic test: a column must have only one distinct value per key,
    e.g. an event must have only one event_date across all its registrations.
    Returns the keys with more than one value (e.g. an event that was rescheduled).

    Usage:
        - name: event_date
          data_tests:
            - single_value_per_key: {key: event_id}
#}
{% test single_value_per_key(model, column_name, key) %}

select
    {{ key }},
    count(distinct {{ column_name }}) as distinct_values
from {{ model }}
group by {{ key }}
having count(distinct {{ column_name }}) > 1

{% endtest %}
