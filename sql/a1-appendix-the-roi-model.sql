-- Appendix: The ROI Model
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER SESSION SET TIMEZONE = UTC;
SELECT
  ROUND(SUM(credits_billed), 4)  AS total_billed_credits,
  ROUND(SUM(IFF(service_type ILIKE '%WAREHOUSE%',
                credits_billed, 0)), 4) AS warehouse_credits,
  COUNT(DISTINCT usage_date)     AS days_covered
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD('day', -30, CURRENT_DATE())
  AND usage_date <  CURRENT_DATE();

-- Volume index shape. Swap the view for what your workload tracks.
SELECT DATE_TRUNC('month', start_time) AS month,
       SUM(bytes) / POWER(1024, 3)     AS gb_processed,
       SUM(credits_used_compute)       AS credits,
       ROUND(SUM(credits_used_compute)
         / NULLIF(SUM(bytes) / POWER(1024, 3), 0), 6)
         AS credits_per_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE service_type = 'PIPE'
  AND start_time >= DATEADD('month', -12, CURRENT_DATE)
GROUP BY 1
ORDER BY 1;
