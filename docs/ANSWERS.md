# Answers to the case

## Part 1: Ingestion and orchestration

### 1.1 Metadata → `ingestion/metadata/gestor_eventos.yml`

**DeltaLoad on `updated_at`.** Rows are updated in place and every update sets `updated_at`, so a
watermark on it captures new registrations and changes (cancellations) while reading ~2k of 400k
rows a day.

### 1.2 Incremental extraction → `ingestion/sql/extract_event_registration.sql`

- **Watermark.** Before the copy, a Lookup reads `WATERMARK_FROM` (the `WATERMARK_TO` of the last
  `Succeeded` run in `AUDIT.LOG_INGESTIONS`) and fixes `WATERMARK_TO = MAX(updated_at)` in the source.
  The new watermark is saved **only after** the copy succeeds. On the first run there is no
  successful run yet, so the lookup starts from `1900-01-01` (full initial load).
- **Failure halfway.** The watermark does not move, so the next run re-reads the same window:
  nothing is lost. Rows already copied by the failed attempt are identical versions and Silver keeps
  one row per registration: nothing is duplicated. A 60-minute overlap re-reads late commits for
  the same reason.
- **What worries me:**
  1. **Hard deletes** are invisible to a watermark (fix: periodic full load of the keys).
  2. **`updated_at` may be text.** The sample has `15/09/2026 09:40` next to ISO dates; if the
     column is VARCHAR in SQL Server, string comparison breaks the watermark. To confirm with the source owner.
  3. **Updates that don't touch `updated_at`** (scripts, bulk fixes) are missed.
  4. **Time zone / DST** of `updated_at` (assumed Europe/Madrid).

### 1.3 Schedule and monitoring → `orchestration/schedule.sql`, `monitoring/daily_ingestion_check.sql`

CRON: `USING CRON 30 3 * * * Europe/Madrid`.
"Usual" = median `ROWS_COPIED` of the successful runs in the previous 28 days; alert below 50 % or
above 200 % of it, on failure, or on 0 rows. Limitation: an object that did not run at all does not
appear; detecting that needs the list of active objects from the metadata.

## Part 2: dbt

| Model | Layer | Materialisation | Why |
|---|---|---|---|
| `stg_gestor_eventos__registrations` | Silver | incremental, merge on `registration_id` | The source updates rows in place, so each batch brings new versions of existing registrations: the merge replaces them. Reads only recent Bronze rows (24h lookback) |
| `fct_event_registrations` | Gold | table | ~400k rows rebuilt daily is cheap; simplest for the layer Power BI reads |
| `dim_event` | Gold | table | Gives one name per event (the source spells it in several ways) |
| `dim_attendee` | Gold | table | Answers *who* attends more than one event; the only Gold model with personal data |

The data problems found in the sample and the decision for each are at the top of the Silver model.

**Tests beyond unique / not_null:**

| Test | Where | What it proves |
|---|---|---|
| Source freshness | Bronze | The daily load really ran |
| `accepted_values` on status (warn) | Silver | A new status in the tool is noticed |
| `not_before` (custom) | Silver | A registration is not updated before it was created |
| `single_value_per_key` (custom, warn) | Silver | An event has only one date (warns on a rescheduled event) |
| `not_masked` (custom) | Silver | dbt read real emails; otherwise every person would get the same `attendee_key` |
| `row_count_matches` (custom) | Silver, Gold | Reconciliation Bronze → Silver → Gold: no row lost or duplicated |
| `relationships` | Gold | Every registration has its event and its person |
| Contracts | Silver, Gold | Column names and types cannot change silently |

Severity by layer: Bronze **warns** (faithful copy), Silver and Gold **fail** the build.

## Part 3: Security

### 3.1 → `security/V1.0__pii_masking.sql`

- **Personal data:** `attendee_email`, `first_name`, `last_name`, `phone` (direct identifiers, tagged
  and masked). `company` is not masked because Marketing needs it (to confirm with the DPO).
- **Where real values are visible:** for `PRO__B__ETL` and `FR_EVENTS_MARKETING` only. In Gold,
  personal data exists only in `dim_attendee`, kept apart from the fact on purpose: the fact serves
  any analysis without identities, and the dimension answers *who* repeats, for Marketing. Analysts
  and Power BI users with other roles see `***MASKED***` (NULL stays NULL, so a missing email is still visible).
- **Minimisation:** `phone` is not carried to Silver; no business question needs it.
- **Where the code lives:** tag, policy and function are governance objects, not data models, so
  they are a **versioned migration (schemachange)** deployed by CI/CD DEV → PRE → PRO **before** dbt.
  The Bronze table is created by the same migration, before the first ADF load, so its columns
  are masked from the first row. dbt attaches the tag to the Silver and `dim_attendee` columns
  (`meta.pii` + post-hook), because a full refresh recreates the table and drops its tags.
- **Power BI:** masking evaluates the Snowflake role of the connection. If Power BI connected with
  one service account, everyone would see what that account sees. So Power BI uses SSO (the user's
  identity is passed to Snowflake): Marketing sees real values, other users see `***MASKED***`.

### 3.2

1. **PRO object owned by a developer or DEV role.** The owner can alter, drop or re-grant the object,
   so a person or a DEV process would control production data outside the versioned deployments.
   Deployments also break (the service role cannot replace an object it does not own) and the
   object is orphaned when the person leaves. Everything in PRO must be owned by PRO service roles.
2. **Unique attendees without the email.** `attendee_key` = keyed SHA-256 of the normalised email,
   from a secure function whose key nobody can read. It is not masked, so Power BI counts
   `DISTINCTCOUNT(attendee_key)`. It must be keyed: a plain `sha2(email)` can be reversed with a
   list of known emails.
