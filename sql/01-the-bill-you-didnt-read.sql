-- The Bill You Didn't Read
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

-- Query A: the whole account, 30 days, by service.
ALTER SESSION SET TIMEZONE = UTC;

SELECT
  service_type,
  ROUND(SUM(credits_used_compute), 1)        AS compute_credits,
  ROUND(SUM(credits_used_cloud_services), 1) AS cloud_credits,
  ROUND(SUM(credits_used), 1)                AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  AND start_time <  CURRENT_DATE()
GROUP BY service_type
ORDER BY total_credits DESC;

-- Query B: warehouse spend, and how much of it was idle.
ALTER SESSION SET TIMEZONE = UTC;

SELECT
  warehouse_name,
  ROUND(SUM(credits_used_compute), 1) AS compute_credits,
  ROUND(SUM(credits_attributed_compute_queries), 1)
    AS query_credits,
  ROUND(SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries), 1) AS idle_credits,
  ROUND(100 * (SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries))
    / NULLIF(SUM(credits_used_compute), 0), 1) AS idle_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  AND end_time <  CURRENT_DATE()
  AND warehouse_id > 0
GROUP BY warehouse_name
ORDER BY idle_credits DESC;

-- Query C: what the meter says you were actually billed.
SELECT
  ROUND(SUM(credits_used_compute), 1)              AS compute,
  ROUND(SUM(credits_used_cloud_services), 1)       AS cloud_svc,
  ROUND(SUM(credits_adjustment_cloud_services), 1) AS adjustment,
  ROUND(SUM(credits_billed), 1)                    AS billed
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD('day', -30, CURRENT_DATE())
  AND usage_date <  CURRENT_DATE();
