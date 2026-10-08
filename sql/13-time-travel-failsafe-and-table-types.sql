-- Time Travel, Fail-safe and Table Types
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT table_catalog, table_schema, table_name,
       active_bytes, time_travel_bytes, failsafe_bytes,
       ROUND(time_travel_bytes / NULLIF(active_bytes, 0), 2)
         AS tt_ratio,
       ROUND(failsafe_bytes / NULLIF(active_bytes, 0), 2)
         AS fs_ratio,
       ROUND((active_bytes + time_travel_bytes
              + failsafe_bytes + retained_for_clone_bytes)
             / POWER(1024, 4), 3) AS total_tb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE active_bytes + time_travel_bytes + failsafe_bytes
      + retained_for_clone_bytes > 0
  AND (time_travel_bytes + failsafe_bytes) > POWER(1024, 3) * 100
ORDER BY (time_travel_bytes + failsafe_bytes) DESC
LIMIT 100;

SELECT table_catalog, table_schema, table_name,
       table_dropped, table_entered_failsafe,
       ROUND(failsafe_bytes / POWER(1024, 4), 3) AS failsafe_tb,
       DATEADD('day', 7, table_entered_failsafe)
         AS billing_ends_estimate
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_dropped IS NOT NULL
  AND failsafe_bytes > 0
ORDER BY failsafe_bytes DESC;

SELECT table_catalog, table_schema, table_name,
       COUNT_IF(table_dropped IS NOT NULL) AS dead_versions,
       SUM(CASE WHEN table_dropped IS NOT NULL
                THEN active_bytes + time_travel_bytes
                     + failsafe_bytes ELSE 0 END)
         AS bytes_from_dead_versions
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
GROUP BY 1, 2, 3
HAVING COUNT_IF(table_dropped IS NOT NULL) > 0
ORDER BY bytes_from_dead_versions DESC
LIMIT 50;

SHOW STREAMS IN ACCOUNT
  ->> SELECT "name", "table_name", "stale", "stale_after"
      FROM $1
      WHERE "stale" = TRUE
         OR "stale_after" < CURRENT_TIMESTAMP();

SHOW TABLES LIKE 'MY_TABLE' IN SCHEMA my_db.my_schema;
SHOW STREAMS LIKE 'MY_STREAM' IN SCHEMA my_db.my_schema;

SELECT table_catalog, table_schema,
       COUNT_IF(is_transient = 'NO')  AS permanent_tables,
       COUNT_IF(is_transient = 'YES') AS transient_tables,
       ROUND(SUM(CASE WHEN is_transient = 'NO'
                THEN active_bytes + time_travel_bytes
                     + failsafe_bytes ELSE 0 END)
             / POWER(1024, 4), 3) AS permanent_tb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE deleted = FALSE
  AND table_dropped IS NULL
GROUP BY 1, 2
ORDER BY permanent_tb DESC
LIMIT 50;

-- 1. Retire any stream first, or it overrides the retention you set.
DROP STREAM IF EXISTS my_db.my_schema.my_stream_on_dim;

-- 2. Zero the retention BEFORE the copy, so the copy is not protected.
ALTER TABLE my_db.my_schema.my_high_churn_dim
  SET DATA_RETENTION_TIME_IN_DAYS = 0;
ALTER TABLE my_db.my_schema.my_high_churn_dim
  SET MAX_DATA_EXTENSION_TIME_IN_DAYS = 0;

-- 3. Build the transient replacement.
CREATE TRANSIENT TABLE my_db.my_schema.dim_new
  DATA_RETENTION_TIME_IN_DAYS = 0
  MAX_DATA_EXTENSION_TIME_IN_DAYS = 0
AS SELECT * FROM my_db.my_schema.my_high_churn_dim;

-- 4. Recreate grants from DDL rather than by hand.
SELECT GET_DDL('TABLE', 'my_db.my_schema.my_high_churn_dim');

-- 5. Cut over atomically so readers never see a gap.
BEGIN;
  ALTER TABLE my_db.my_schema.my_high_churn_dim
    RENAME TO my_high_churn_dim_old;
  ALTER TABLE my_db.my_schema.dim_new
    RENAME TO my_high_churn_dim;
COMMIT;

-- 6. Drop the old table last.
DROP TABLE my_db.my_schema.my_high_churn_dim_old;

CREATE OR REPLACE TABLE my_db.my_schema.dim_backup
  DATA_RETENTION_TIME_IN_DAYS = 1
AS SELECT * FROM my_db.my_schema.my_high_churn_dim;

CREATE OR REPLACE TRANSIENT TABLE my_db.my_schema.my_high_churn_dim
  DATA_RETENTION_TIME_IN_DAYS = 0
AS SELECT * FROM my_db.my_schema.dim_backup
   AT(TIMESTAMP => DATEADD('hour', -6, CURRENT_TIMESTAMP()));

SELECT table_catalog, table_schema, table_name,
       created, retention_time, table_type, is_transient
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
WHERE deleted IS NULL
  AND retention_time > 1
  AND created >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY created DESC;

SELECT usage_date,
       ROUND(storage_bytes / POWER(1024, 4), 3)  AS storage_tb,
       ROUND(failsafe_bytes / POWER(1024, 4), 3) AS failsafe_tb,
       ROUND((storage_bytes + failsafe_bytes)
             / POWER(1024, 4), 3)               AS billable_tb
FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE
WHERE usage_date >= DATEADD('day', -90, CURRENT_DATE())
ORDER BY usage_date;
