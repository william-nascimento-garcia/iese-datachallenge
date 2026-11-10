-- Parameterised source query run by the generic ADF Copy activity for task 1310.
--
--   @{pipeline().parameters.watermark_from}  WATERMARK_TO of the last 'Succeeded' run (Snowflake lookup below)
--   @{pipeline().parameters.watermark_to}    read by a Lookup activity BEFORE the copy (query below)
--
-- Window: (watermark_from - 60 minutes, watermark_to]
--   * the upper bound is fixed before the copy, so rows changed during the copy go to the next run
--   * the 60-minute overlap re-reads late commits; the duplicates it creates are removed in Silver

SELECT
    registration_id,
    event_id,
    event_name,
    event_date,
    attendee_email,
    first_name,
    last_name,
    phone,
    company,
    registration_status,
    registered_at,
    updated_at
FROM dbo.EVENT_REGISTRATION
WHERE updated_at >  DATEADD(MINUTE, -60, CAST('@{pipeline().parameters.watermark_from}' AS DATETIME2))
  AND updated_at <= CAST('@{pipeline().parameters.watermark_to}' AS DATETIME2);


-- Lookup activity, run before the copy: upper bound of the window, from the source's own clock.
SELECT CONVERT(VARCHAR(27), MAX(updated_at), 121) AS watermark_to
FROM dbo.EVENT_REGISTRATION;


-- Lookup activity in Snowflake: lower bound of the window.
-- First run: there is no successful run yet, so it starts from 1900-01-01 = full initial load.
SELECT COALESCE(MAX(WATERMARK_TO), '1900-01-01 00:00:00') AS watermark_from
FROM AUDIT.LOG_INGESTIONS
WHERE SOURCE_SYSTEM = 'GESTOR_EVENTOS'
  AND OBJECT_NAME   = 'EVENT_REGISTRATION'
  AND STATUS        = 'Succeeded';
