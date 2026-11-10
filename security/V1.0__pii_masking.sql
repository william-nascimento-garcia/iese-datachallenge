-- Versioned migration (schemachange), deployed by CI/CD DEV -> PRE -> PRO before dbt.
-- {{ env }} = DEV | PRE | PRO. Nobody runs this by hand in PRO.
--
-- Personal data in EVENT_REGISTRATION:
--   attendee_email, first_name, last_name, phone  direct identifiers -> tagged PII, masked
--   company                                        not masked: B2B attribute Marketing needs (confirm with DPO)
--   registration_id, attendee_key                  pseudonymous identifiers, not masked

create schema if not exists {{ env }}_FW_METADATA_DTP.GOVERNANCE;

-- 1. Tag: classifies the column.
create tag if not exists {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII
    allowed_values 'email', 'name', 'phone'
    comment = 'Personal data (GDPR). Masked by policy PII_MASK.';

-- 2. Masking policy: real values only for the ETL service role and Events Marketing.
create masking policy if not exists {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII_MASK
    as (val string) returns string ->
    case
        when is_role_in_session('{{ env }}__B__ETL')   then val
        when is_role_in_session('FR_EVENTS_MARKETING') then val
        when val is null                               then null   -- "missing" stays visible
        else '***MASKED***'
    end;

-- 3. Attach the policy to the tag: any column tagged PII is masked automatically.
alter tag {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII
    set masking policy {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII_MASK;

-- 4. Bronze table: created here, by the versioned deployment, BEFORE the first ADF load.
--    ADF only appends to it, so the columns are tagged (and masked) from the very first row.
--    Silver and Gold are tagged by dbt (meta.pii).
create table if not exists {{ env }}_BRONZE_DTP.GESTOR_EVENTOS.EVENT_REGISTRATION (
    registration_id      varchar,
    event_id             varchar,
    event_name           varchar,
    event_date           varchar,
    attendee_email       varchar,
    first_name           varchar,
    last_name            varchar,
    phone                varchar,
    company              varchar,
    registration_status  varchar,
    registered_at        varchar,
    updated_at           varchar,
    _loaded_at           timestamp_ntz,
    _batch_id            varchar
);

alter table {{ env }}_BRONZE_DTP.GESTOR_EVENTOS.EVENT_REGISTRATION modify column
    attendee_email set tag {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII = 'email',
    first_name     set tag {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII = 'name',
    last_name      set tag {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII = 'name',
    phone          set tag {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII = 'phone';

grant usage on schema {{ env }}_FW_METADATA_DTP.GOVERNANCE to role {{ env }}__B__ETL;
grant apply on tag {{ env }}_FW_METADATA_DTP.GOVERNANCE.PII to role {{ env }}__B__ETL;

-- 5. Pseudonymisation for 3.2: count unique attendees without exposing the email.
--    SECURE: callers can execute it but cannot read the body, which holds the key.
--    {{ pepper }} is injected at deploy time from Azure Key Vault; it is never in Git.
create or replace secure function {{ env }}_FW_METADATA_DTP.GOVERNANCE.PSEUDONYMIZE(email varchar)
    returns varchar
as
$$
    case
        when nullif(trim(email), '') is null then null
        else sha2('{{ pepper }}' || '|' || lower(trim(email)), 256)
    end
$$;

grant usage on function {{ env }}_FW_METADATA_DTP.GOVERNANCE.PSEUDONYMIZE(varchar) to role {{ env }}__B__ETL;
