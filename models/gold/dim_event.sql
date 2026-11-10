{#
    GOLD: one row per event.
    The source repeats the event attributes on every registration and they are not consistent
    ('Family Business Forum', 'Family Business Forum ', 'family business forum').
      - name: the most frequent spelling wins, ties broken by the most recent
      - date: taken from the most recently updated registration (latest information wins);
        the Silver test single_value_per_key warns when an event has more than one date
#}

with registrations as (

    select * from {{ ref('stg_gestor_eventos__registrations') }}

),

names as (

    select event_id, event_name, count(*) as times_seen, max(updated_at) as last_seen
    from registrations
    group by event_id, event_name
    qualify row_number() over (partition by event_id order by times_seen desc, last_seen desc) = 1

),

dates as (

    select event_id, event_date
    from registrations
    qualify row_number() over (partition by event_id order by updated_at desc, registration_id desc) = 1

)

select
    d.event_id::varchar      as event_id,
    n.event_name::varchar    as event_name,
    d.event_date::date       as event_date
from dates as d
left join names as n
    on n.event_id = d.event_id
