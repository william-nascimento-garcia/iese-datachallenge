{#
    Custom generic test: the column must not contain the masking placeholder.
    Silver reads emails from Bronze, where they are masked. If dbt ran with a role that sees
    '***MASKED***', every email would hash to the same attendee_key and all people would merge
    into one. This test stops the build in that case. dbt must always run as {env}__B__ETL.

    Usage:
        - name: attendee_email
          data_tests: [not_masked]
#}
{% test not_masked(model, column_name) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} = '***MASKED***'

{% endtest %}
