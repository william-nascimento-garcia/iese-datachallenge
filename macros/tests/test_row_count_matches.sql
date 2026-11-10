{#
    Custom generic test: reconciliation between layers.
    The row count of this model must equal an expression evaluated on the model it comes from,
    proving that no row was lost or duplicated by deduplication, filters or joins.

    Usage (on a model):
        data_tests:
          - row_count_matches:
              compare_model: ref('stg_gestor_eventos__registrations')
              compare_expression: "count(*)"
#}
{% test row_count_matches(model, compare_model, compare_expression='count(*)') %}

with this_model as (
    select count(*) as row_count from {{ model }}
),
other_model as (
    select {{ compare_expression }} as row_count from {{ compare_model }}
)
select
    this_model.row_count  as model_rows,
    other_model.row_count as expected_rows
from this_model
cross join other_model
where this_model.row_count <> other_model.row_count

{% endtest %}
