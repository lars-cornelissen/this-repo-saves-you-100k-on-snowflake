-- Auto-Suspend and Idle Time
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER WAREHOUSE bi_wh SET AUTO_SUSPEND = 60;

SELECT
  warehouse_name,
  SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries) AS idle_cost
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('days', -10, CURRENT_DATE())
  AND end_time < CURRENT_DATE()
GROUP BY warehouse_name
ORDER BY idle_cost DESC;

SELECT
  warehouse_name,
  ROUND(SUM(credits_used_compute), 1) AS total_credits,
  ROUND(SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries), 1) AS idle_credits,
  ROUND(100 * (SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries))
    / NULLIF(SUM(credits_used_compute), 0), 1) AS idle_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('days', -30, CURRENT_DATE())
  AND end_time < CURRENT_DATE()
GROUP BY warehouse_name
HAVING SUM(credits_used_compute) > 0
ORDER BY idle_credits DESC;

SELECT
  name,
  size,
  state,
  auto_suspend,
  auto_resume,
  min_cluster_count,
  max_cluster_count
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSES())
WHERE auto_suspend IS NULL
   OR auto_suspend = 0
   OR auto_suspend > 300
ORDER BY size;

WITH q AS (
  SELECT
    warehouse_name,
    start_time,
    LAG(end_time) OVER (
      PARTITION BY warehouse_name ORDER BY start_time
    ) AS prev_end
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
  WHERE warehouse_name = 'BI_WH'
    AND start_time >= DATEADD('days', -7, CURRENT_DATE())
    AND warehouse_size IS NOT NULL
)
SELECT
  ROUND(AVG(gap_sec), 0)  AS avg_gap_sec,
  ROUND(MEDIAN(gap_sec), 0) AS median_gap_sec,
  COUNT_IF(gap_sec < 120) AS gaps_under_2min,
  COUNT_IF(gap_sec BETWEEN 120 AND 300) AS gaps_2_to_5min,
  COUNT(*) AS total_gaps
FROM (
  SELECT
    DATEDIFF('second', prev_end, start_time) AS gap_sec
  FROM q
  WHERE prev_end IS NOT NULL
)
WHERE gap_sec > 0;

CREATE OR REPLACE RESOURCE MONITOR bi_guard
  WITH CREDIT_QUOTA = 500
  TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE bi_wh SET RESOURCE_MONITOR = bi_guard;

SELECT
  warehouse_name,
  ROUND(100 * (SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries))
    / NULLIF(SUM(credits_used_compute), 0), 1) AS idle_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('days', -7, CURRENT_DATE())
  AND end_time < CURRENT_DATE()
GROUP BY warehouse_name
HAVING idle_pct > 50
ORDER BY idle_pct DESC;
