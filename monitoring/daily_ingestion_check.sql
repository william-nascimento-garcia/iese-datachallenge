-- Morning check for Gestor Eventos. Returns only the objects that need attention (empty = all good).
--
-- For the latest run of each object in the last 24 hours:
--   FAILED       STATUS = 'Failed'
--   ZERO_ROWS    succeeded but copied 0 rows (~2k changes per day are expected)
--   LOW_VOLUME   copied less than 50% of usual
--   HIGH_VOLUME  copied more than 200% of usual (bulk update in the source, reset watermark...)
--
-- "Usual" = median ROWS_COPIED of the successful runs in the previous 28 days.
-- Median, so one bulk reload does not distort it; 28 days = four of each weekday.

with runs as (
    select *
    from AUDIT.LOG_INGESTIONS
    where SOURCE_SYSTEM = 'GESTOR_EVENTOS'
      and START_TS >= dateadd('day', -29, current_timestamp())
),

latest_run as (
    select *
    from runs
    where START_TS >= dateadd('hour', -24, current_timestamp())
    qualify row_number() over (partition by OBJECT_NAME order by START_TS desc) = 1
),

usual as (
    select OBJECT_NAME, median(ROWS_COPIED) as usual_rows
    from runs
    where STATUS = 'Succeeded'
      and START_TS < dateadd('hour', -24, current_timestamp())
    group by OBJECT_NAME
)

select
    l.OBJECT_NAME,
    l.RUN_ID,
    l.START_TS,
    l.STATUS,
    l.ROWS_COPIED,
    u.usual_rows,
    l.ERROR_MESSAGE,
    case
        when l.STATUS = 'Failed'                then 'FAILED'
        when l.ROWS_COPIED = 0                  then 'ZERO_ROWS'
        when l.ROWS_COPIED < 0.5 * u.usual_rows then 'LOW_VOLUME'
        when l.ROWS_COPIED > 2.0 * u.usual_rows then 'HIGH_VOLUME'
    end as alert
from latest_run as l
left join usual as u
    on u.OBJECT_NAME = l.OBJECT_NAME
where alert is not null
order by l.OBJECT_NAME;
