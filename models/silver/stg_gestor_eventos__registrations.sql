{#
    SILVER: one clean, typed row per registration (latest version).

    Problems found in the sample and decisions:
      - Duplicates (24 Bronze rows -> 20 registrations):
          R-1003 twice in the same batch (exact copy), R-1014 re-sent unchanged in B-0002 (overlap)
          -> keep one row per registration_id
      - New versions of a row (not duplicates): R-1005 registered -> cancelled,
          R-1009 waitlisted -> registered -> the latest updated_at wins
      - Mixed date formats ('15/09/2026 09:40')
          -> parse ISO and DD/MM/YYYY; unknown format -> NULL -> not_null test fails
      - Email with spaces or capitals (' JORDI.SALA@Globex.com ') -> trim + lower
      - Status in different case ('CANCELLED') -> normalised + accepted_values test
      - Event name with trailing space or lower case -> trimmed here; one name per event in dim_event
      - Registration without email (R-1004) -> kept (it counts for the event), attendee_key NULL
      - Test registration (R-1006: test@iese.edu, TEST TEST) -> removed here: it is not real
          business data. The rule is the var test_record_condition (dbt_project.yml), shared with
          the reconciliation test so both always agree.
      - Phone -> not carried to Silver: no business question needs it (GDPR data minimisation)
      - Email and names -> tagged PII (meta.pii) -> masked except for ETL and Events Marketing

    Materialisation: incremental merge on registration_id. The source updates rows in place, so
    every batch brings new versions of existing registrations: the merge replaces them.
    Each run reads only the Bronze rows loaded since the last run, with a 24h lookback so a
    late or re-run batch is never skipped (re-reading is harmless: the merge is idempotent).
#}

{{ config(
    materialized='incremental',
    unique_key='registration_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    contract={'enforced': true}
) }}

with source as (

    select *
    from {{ source('gestor_eventos', 'event_registration') }}
    where not ({{ var('test_record_condition') }})
    {% if is_incremental() %}
      and _loaded_at > (select dateadd('hour', -24, max(_loaded_at)) from {{ this }})
    {% endif %}

),

cleaned as (

    select
        {{ clean_text('registration_id') }}                      as registration_id,
        {{ clean_text('event_id') }}                             as event_id,
        {{ clean_text('event_name') }}                           as event_name,
        {{ parse_date('event_date') }}                           as event_date,
        lower({{ clean_text('attendee_email') }})                as attendee_email,
        {{ clean_text('first_name') }}                           as first_name,
        {{ clean_text('last_name') }}                            as last_name,
        {{ clean_text('company') }}                              as company,
        {{ normalize_status('registration_status') }}            as registration_status,
        {{ parse_timestamp('registered_at') }}                   as registered_at,
        {{ parse_timestamp('updated_at') }}                      as updated_at,
        _loaded_at::timestamp_ntz                                as _loaded_at
    from source

)

-- Explicit types: text is varchar, dates are date, timestamps are timestamp_ntz.
-- The contract in the .yml enforces them: a type change fails the build.
select
    registration_id::varchar                                     as registration_id,
    event_id::varchar                                            as event_id,
    event_name::varchar                                          as event_name,
    event_date::date                                             as event_date,
    {{ pseudonymize('attendee_email') }}::varchar                as attendee_key,
    attendee_email::varchar                                      as attendee_email,
    first_name::varchar                                          as first_name,
    last_name::varchar                                           as last_name,
    company::varchar                                             as company,
    registration_status::varchar                                 as registration_status,
    registered_at::timestamp_ntz                                 as registered_at,
    updated_at::timestamp_ntz                                    as updated_at,
    _loaded_at::timestamp_ntz                                    as _loaded_at
from cleaned
-- latest version per registration. NULLS FIRST on purpose: a version whose updated_at could not
-- be parsed wins, lands with updated_at NULL and fails the not_null test, instead of being
-- silently ignored.
qualify row_number() over (
    partition by registration_id
    order by updated_at desc nulls first, _loaded_at desc
) = 1
