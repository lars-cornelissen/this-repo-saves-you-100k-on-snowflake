-- The Cache Layers
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT DISTINCT(severity) FROM weather_events;
SELECT DISTINCT(severity) FROM weather_events;
SELECT DISTINCT(severity) FROM weather_events we;
select distinct(severity) from weather_events;

WITH runs AS (
  SELECT
    MD5(query_text) AS text_fp,
    query_text,
    start_time,
    warehouse_name,
    bytes_scanned,
    total_elapsed_time,
    LAG(bytes_scanned) OVER (
      PARTITION BY MD5(query_text) ORDER BY start_time
    ) AS prev_bytes_scanned
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
  WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    AND query_type = 'SELECT'
    AND execution_status = 'success'
)
SELECT *
FROM runs
WHERE prev_bytes_scanned > 0 AND bytes_scanned = 0
ORDER BY start_time DESC
LIMIT 200;

SELECT warehouse_name
  ,COUNT(*) AS query_count
  ,SUM(bytes_scanned) AS bytes_scanned
  ,SUM(bytes_scanned * percentage_scanned_from_cache)
    AS bytes_from_cache
  ,SUM(bytes_scanned * percentage_scanned_from_cache)
    / SUM(bytes_scanned) AS cache_fraction
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(month, -1, CURRENT_TIMESTAMP())
  AND bytes_scanned > 0
GROUP BY 1
ORDER BY 5;

SELECT warehouse_name,
  COUNT_IF(bytes_spilled_to_local_storage > 0) AS local_spill_queries,
  COUNT_IF(bytes_spilled_to_remote_storage > 0) AS remote_spill_queries,
  ROUND(SUM(bytes_spilled_to_local_storage)
    / POWER(1024, 3), 2) AS local_spill_gib
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -14, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
GROUP BY 1
HAVING local_spill_queries > 0
ORDER BY local_spill_gib DESC;

SELECT DATE_TRUNC('week', start_time) AS week,
  COUNT_IF(prev_bytes_scanned > 0 AND bytes_scanned = 0)
    AS reuse_events
FROM (
  SELECT start_time, bytes_scanned,
    LAG(bytes_scanned) OVER (
      PARTITION BY MD5(query_text) ORDER BY start_time
    ) AS prev_bytes_scanned
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
  WHERE start_time >= DATEADD(day, -90, CURRENT_TIMESTAMP())
    AND query_type = 'SELECT'
    AND execution_status = 'success'
)
GROUP BY 1
ORDER BY week;
