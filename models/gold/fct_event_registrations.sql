{#
    GOLD: one row per registration for Power BI.

      - registrations per event   -> count rows by event_id / registration_status
      - cancellations             -> is_cancelled (and is_cancelled_but_still_attending)
      - people in several events  -> attendee_key -> dim_attendee.is_repeat_attendee

    No personal data in the fact: a person is the pseudonymous attendee_key (DISTINCTCOUNT).
    Who the person is lives only in dim_attendee, masked except for Events Marketing.
    "Attending" = status registered or attended (the source has no check-in data; assumption).

    Materialisation: table. ~400k rows rebuilt daily is cheap and keeps the layer Power BI reads simple.
#}

with registrations as (

    select
        *,
        registration_status in ('registered', 'attended') as is_attending
    from {{ ref('stg_gestor_eventos__registrations') }}

),

-- a person can register twice for one event and cancel only one registration (Paolo Rossi, EV-2026-040)
person_event as (

    select attendee_key, event_id, count_if(is_attending) as attending_registrations
    from registrations
    where attendee_key is not null
    group by attendee_key, event_id

)

select
    r.registration_id::varchar                                              as registration_id,
    r.event_id::varchar                                                     as event_id,
    r.attendee_key::varchar                                                 as attendee_key,
    r.registration_status::varchar                                          as registration_status,
    (r.registration_status = 'cancelled')::boolean                          as is_cancelled,
    coalesce(r.registration_status = 'cancelled'
             and pe.attending_registrations > 0, false)::boolean            as is_cancelled_but_still_attending,
    r.registered_at::timestamp_ntz                                          as registered_at,
    r.event_date::date                                                      as event_date,
    -- last change of the row, not necessarily the cancellation time: the source keeps no history
    r.updated_at::timestamp_ntz                                             as last_status_change_at
from registrations as r
left join person_event as pe
    on pe.attendee_key = r.attendee_key and pe.event_id = r.event_id
