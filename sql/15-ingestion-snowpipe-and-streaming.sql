-- Ingestion, Snowpipe and Streaming
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT
    pipe_name,
    SUM(credits_used)      AS credits_30d,
    SUM(bytes_inserted)    AS bytes_inserted_30d,
    SUM(files_inserted)    AS files_inserted_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 2 DESC;

SELECT
    DATE_TRUNC('day', start_time) AS day,
    pipe_name,
    SUM(credits_used)   AS credits,
    SUM(bytes_inserted) AS bytes_inserted,
    SUM(files_inserted) AS files_inserted
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
HAVING SUM(credits_used) > 0
   AND SUM(bytes_inserted) = 0
   AND SUM(files_inserted) = 0
ORDER BY credits DESC;

SELECT
    name,
    SUM(credits_used) AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE service_type = 'SNOWPIPE_STREAMING'
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 2 DESC;

SELECT
    usage_date,
    ROUND(AVERAGE_STAGE_BYTES / POWER(1024, 4), 3) AS stage_tib
FROM SNOWFLAKE.ACCOUNT_USAGE.STAGE_STORAGE_USAGE_HISTORY
WHERE usage_date >= DATEADD('day', -90, CURRENT_DATE())
ORDER BY usage_date DESC;

SELECT
    stage_type,
    entity_name,
    ROUND(bytes / POWER(1024, 3), 2)               AS gib,
    file_count,
    ROUND(bytes / NULLIF(file_count, 0) / 1024, 1) AS avg_kib_per_file,
    DATEDIFF(day, min_last_modified, CURRENT_TIMESTAMP())
        AS oldest_file_days
FROM SNOWFLAKE.ACCOUNT_USAGE.STAGE_STORAGE_USAGE_DETAILS
WHERE usage_date = CURRENT_DATE() - 1
  AND file_count > 1000
ORDER BY bytes DESC;

ALTER TABLE my_db.raw.orders
  SET STAGE_COPY_OPTIONS = (PURGE = TRUE);

-- Verify before removing: did the files actually load?
SELECT file_name, status, row_count, error_count, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'MY_DB.RAW.ORDERS',
       START_TIME => DATEADD(day, -2, CURRENT_TIMESTAMP())))
ORDER BY last_load_time DESC;

CREATE OR REPLACE TASK my_db.ops.snapshot_stage_usage
  WAREHOUSE = my_admin_wh
  SCHEDULE  = 'USING CRON 30 3 * * * UTC'
AS
  CREATE OR REPLACE TABLE my_db.ops.stage_usage_daily AS
  SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.STAGE_STORAGE_USAGE_DETAILS
  WHERE usage_date = CURRENT_DATE() - 1;

ALTER TASK my_db.ops.snapshot_stage_usage RESUME;

SELECT
    DATE_TRUNC('day', start_time) AS day,
    SUM(credits_used)             AS credits,
    SUM(bytes_inserted)           AS bytes_inserted,
    ROUND(SUM(credits_used)
      / NULLIF(SUM(bytes_inserted) / POWER(1024, 3), 0), 6)
        AS credits_per_gib
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;
