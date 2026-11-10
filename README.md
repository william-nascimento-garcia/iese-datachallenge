# Gestor Eventos → Snowflake: event registrations

```
Gestor Eventos (SQL Server) ─ ADF DeltaLoad on updated_at ─▶ BRONZE   append, all versions
                                                       dbt ─▶ SILVER   stg_gestor_eventos__registrations (incremental merge)
                                                       dbt ─▶ GOLD     fct_event_registrations + dim_event + dim_attendee ─▶ Power BI
```

Written answers per part: [`docs/ANSWERS.md`](docs/ANSWERS.md).

## Main decisions

- **DeltaLoad on `updated_at`** with a 60-minute overlap. Overlaps and re-runs create duplicates in Bronze on purpose; Silver keeps one row per registration, so the pipeline is idempotent.
- **Silver**: one clean row per registration, latest version. Every data problem in the sample is listed with its decision at the top of the model.
- **Gold**: one fact + `dim_event` + `dim_attendee`. The fact has no personal data (people are the pseudonymous `attendee_key`). Identity lives only in `dim_attendee`, because the business asks *who* attends more than one event; its email and names are masked for everyone except Events Marketing.
- **Tests by layer**: Bronze warns, Silver and Gold fail. Reconciliation between layers, accepted values, chronology, one date per event, relationships, contracts in Silver and Gold.
- **GDPR**: email and names tagged and masked (real values only for `PRO__B__ETL` and `FR_EVENTS_MARKETING`), phone not carried to Silver (minimisation), keyed pseudonymisation.

## Assumptions

- Bronze columns are VARCHAR; timestamps are Europe/Madrid; `dd/mm/yyyy` dates are European.
- "Attending" = status `registered` or `attended` (no check-in data in the source).
- One email = one person. A registration without email counts for its event, not as a known person.
- Test records = `test@…` emails or `TEST TEST` names; removed in Silver (rule in `dbt_project.yml`).
- dbt always runs as `{env}__B__ETL` (it must read real emails to build `attendee_key`; the `not_masked` test enforces it).
- Roles `{env}__B__ETL`, `FR_EVENTS_MARKETING`, `ANALYST` and schema `{env}_FW_METADATA_DTP.GOVERNANCE` exist.
- Power BI connects with SSO (identity passed to Snowflake), so masking follows the person who opens the report.

## Skipped / with more time

- Detect hard deletes (periodic full load of the keys).
- Keep status history (snapshot), to know the real cancellation date.
- Ingest the tool's event table as the source of truth for event names and dates.
- Right-to-erasure process, CI/CD pipeline, alert when an object does not run at all.

## Repo layout

```
ingestion/metadata/   ADF metadata entry         ingestion/sql/   source query
orchestration/        Snowflake Task CRON        monitoring/      morning check on AUDIT.LOG_INGESTIONS
models/bronze/        source, freshness, warn tests
models/silver/        stg_gestor_eventos__registrations + tests
models/gold/          fct_event_registrations, dim_event, dim_attendee + tests
macros/               cleaning, privacy (pseudonymise, PII tags), schema naming, custom tests
security/             tag + masking policy + pseudonymisation function
analysis/             exploratory analysis of the sample (pandas)
```
