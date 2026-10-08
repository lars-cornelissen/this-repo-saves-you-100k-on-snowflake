-- Sizing and Right-Sizing
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT
  warehouse_name,
  warehouse_size,
  COUNT(*) AS queries,
  ROUND(MEDIAN(execution_time) / 1000.0, 2) AS median_sec,
  ROUND(SUM(bytes_spilled_to_local_storage)
    / POWER(1024, 3), 2) AS local_spill_gib,
  ROUND(SUM(bytes_spilled_to_remote_storage)
    / POWER(1024, 3), 2) AS remote_spill_gib
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
  AND execution_time > 0
GROUP BY 1, 2
ORDER BY remote_spill_gib DESC;

WITH load AS (
  SELECT warehouse_name,
    AVG(avg_running) AS running_load,
    AVG(avg_queued_load) AS queued_load,
    SUM(IFF(avg_running < 1, 1, 0)) / COUNT(*) AS pct_below_1
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
  WHERE start_time >= DATEADD('day', -14, CURRENT_TIMESTAMP())
  GROUP BY 1
)
SELECT warehouse_name,
  ROUND(running_load, 3) AS running_load,
  ROUND(queued_load, 3) AS queued_load,
  ROUND(pct_below_1, 3) AS pct_intervals_below_1
FROM load
WHERE running_load < 1 AND queued_load = 0
ORDER BY pct_below_1 DESC;

SELECT
  query_hash,
  warehouse_size,
  COUNT(*) AS runs,
  ROUND(MEDIAN(execution_time) / 1000.0, 2) AS median_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND query_hash = '<your_query_hash>'
  AND execution_status = 'SUCCESS'
GROUP BY 1, 2
HAVING COUNT(*) >= 3
ORDER BY median_sec;

ALTER WAREHOUSE transform_wh SET
  WAREHOUSE_SIZE = 'X-LARGE'
  AUTO_SUSPEND   = 60;

SELECT
  DATE_TRUNC('week', start_time) AS week,
  warehouse_name,
  warehouse_size,
  COUNT(*) AS queries,
  ROUND(MEDIAN(execution_time) / 1000.0, 2) AS median_sec,
  ROUND(SUM(bytes_spilled_to_local_storage)
    / POWER(1024, 3), 3) AS local_spill_gib
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
  AND warehouse_name = 'TRANSFORM_WH'
GROUP BY 1, 2, 3
ORDER BY week DESC, median_sec DESC;
