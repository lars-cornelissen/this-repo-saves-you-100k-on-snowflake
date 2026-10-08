-- The Ten Levers, Ranked by Your Own Data
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER SESSION SET TIMEZONE = UTC;

WITH idle_time AS (
  SELECT
    'idle_time' AS lever,
    SUM(credits_used_compute)
      - SUM(credits_attributed_compute_queries) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND end_time <  CURRENT_DATE()
    AND warehouse_id > 0
    AND credits_attributed_compute_queries IS NOT NULL
),
short_queries AS (
  SELECT
    warehouse_name,
    AVG(total_elapsed_time) / 1000 AS avg_seconds
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND warehouse_size IS NOT NULL
  GROUP BY warehouse_name
),
sizing AS (
  SELECT
    'sizing' AS lever,
    SUM(w.credits_attributed_compute_queries) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY w
  JOIN short_queries s
    ON s.warehouse_name = w.warehouse_name
  WHERE w.start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND w.end_time <  CURRENT_DATE()
    AND w.warehouse_id > 0
    AND s.avg_seconds < 10
),
schedule AS (
  SELECT
    'schedule' AS lever,
    SUM(credits_used_compute) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND end_time <  CURRENT_DATE()
    AND warehouse_id > 0
    AND (DAYOFWEEKISO(start_time) > 5
      OR HOUR(start_time) < 6
      OR HOUR(start_time) >= 20)
),
repeated AS (
  SELECT
    query_parameterized_hash,
    SUM(bytes_scanned) AS bytes_scanned,
    COUNT(*)           AS runs
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  GROUP BY query_parameterized_hash
  HAVING COUNT(*) > 20
     AND SUM(bytes_scanned) > 1000000000000
),
full_refresh AS (
  SELECT
    'full_refresh' AS lever,
    SUM(a.credits_attributed_compute) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY a
  JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q
    ON q.query_id = a.query_id
  JOIN repeated r
    ON r.query_parameterized_hash = q.query_parameterized_hash
  WHERE a.start_time >= DATEADD('day', -30, CURRENT_DATE())
),
unused_assets AS (
  SELECT
    'unused_assets' AS lever,
    SUM(credits_used) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND service_type IN ('MATERIALIZED_VIEW','SEARCH_OPTIMIZATION')
),
storage_history AS (
  SELECT
    'storage_history' AS lever,
    (SUM(time_travel_bytes) + SUM(failsafe_bytes))
      / 1099511627776 * 11.5 AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
),
ingestion AS (
  SELECT
    'ingestion' AS lever,
    SUM(credits_used) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND service_type IN ('PIPE','SNOWPIPE_STREAMING')
),
query_tuning AS (
  SELECT
    'query_tuning' AS lever,
    SUM(a.credits_attributed_compute) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY a
  JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q
    ON q.query_id = a.query_id
  WHERE a.start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND q.bytes_spilled_to_remote_storage > 0
    AND q.query_acceleration_upper_limit_scale_factor IS NULL
),
serverless_2x AS (
  SELECT
    'serverless_2x' AS lever,
    SUM(credits_used) AS pool_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND service_type IN ('AUTO_CLUSTERING','MATERIALIZED_VIEW',
      'SEARCH_OPTIMIZATION','BACKUP','COPY_FILES',
      'DATA_QUALITY_MONITORING')
),
rate_edition AS (
  SELECT
    'rate_edition' AS lever,
    CAST(NULL AS NUMBER(38,2)) AS pool_credits
)
SELECT
  lever,
  ROUND(pool_credits, 1) AS pool_credits
FROM (
  SELECT * FROM idle_time
  UNION ALL SELECT * FROM sizing
  UNION ALL SELECT * FROM schedule
  UNION ALL SELECT * FROM full_refresh
  UNION ALL SELECT * FROM unused_assets
  UNION ALL SELECT * FROM storage_history
  UNION ALL SELECT * FROM ingestion
  UNION ALL SELECT * FROM query_tuning
  UNION ALL SELECT * FROM serverless_2x
  UNION ALL SELECT * FROM rate_edition
)
ORDER BY pool_credits DESC NULLS LAST;

-- Effective price per compute credit, from the organization views.
SELECT
  DATE_TRUNC('month', usage_date) AS month,
  ROUND(SUM(usage_in_currency) / NULLIF(SUM(usage), 0), 4)
    AS effective_usd_per_credit
FROM SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY
WHERE usage_date >= DATEADD('month', -6, CURRENT_DATE())
  AND rating_type = 'compute'
GROUP BY 1
ORDER BY 1;

SELECT
  DATE_TRUNC('month', start_time) AS month,
  SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries) AS idle_credits,
  ROUND(SUM(credits_used_compute)
    / NULLIF(SUM(credits_attributed_compute_queries), 0), 2)
    AS idle_multiplier
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('month', -6, CURRENT_DATE())
  AND warehouse_id > 0
GROUP BY 1
ORDER BY 1 DESC;
