{#
    Custom generic test: chronological consistency between two columns of the same row,
    e.g. a registration cannot be updated or cancelled before it was created.

    Usage:
        - name: updated_at
          data_tests:
            - not_before: {column: registered_at}
#}
{% test not_before(model, column_name, column) %}

select
    {{ column_name }} as later_value,
    {{ column }}      as earlier_value
from {{ model }}
where {{ column_name }} < {{ column }}

{% endtest %}
