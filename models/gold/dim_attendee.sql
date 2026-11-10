{#
    GOLD: one row per person, for "who attends more than one event".

    The ONLY Gold model with personal data, on purpose: identity is kept apart from the fact.
    Email and names are tagged PII in the .yml -> masked for everyone except
    PRO__B__ETL and FR_EVENTS_MARKETING. Phone is not included (minimisation).
    Attributes come from the person's most recent registration.
    "Attending" = status registered or attended (no check-in data in the source; assumption).
#}

with registrations as (

    select *
    from {{ ref('stg_gestor_eventos__registrations') }}
    where attendee_key is not null

),

latest_details as (

    select attendee_key, attendee_email, first_name, last_name, company
    from registrations
    qualify row_number() over (partition by attendee_key order by updated_at desc, registration_id desc) = 1

),

activity as (

    select
        attendee_key,
        count(distinct case when registration_status in ('registered', 'attended') then event_id end)
            as events_attending
    from registrations
    group by attendee_key

)

select
    d.attendee_key::varchar                     as attendee_key,
    d.attendee_email::varchar                   as attendee_email,
    d.first_name::varchar                       as first_name,
    d.last_name::varchar                        as last_name,
    d.company::varchar                          as company,
    a.events_attending::number(10, 0)           as events_attending,
    (a.events_attending > 1)::boolean           as is_repeat_attendee
from latest_details as d
inner join activity as a
    on a.attendee_key = d.attendee_key
