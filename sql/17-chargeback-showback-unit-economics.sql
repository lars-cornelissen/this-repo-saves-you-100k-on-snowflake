-- Chargeback, Showback and Unit Economics
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

-- How much of warehouse compute does attribution reach?
SELECT
  ROUND(SUM(credits_used_compute), 1)               AS wh_compute,
  ROUND(SUM(credits_attributed_compute_queries), 1) AS attributed,
  ROUND(100 * SUM(credits_attributed_compute_queries)
    / NULLIF(SUM(credits_used_compute), 0), 1)      AS pct_covered
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  AND end_time < CURRENT_DATE();

-- Allocation coverage. Replace COST_CENTER with your allocation tag.
WITH tagged AS (
  SELECT wmh.credits_used_compute AS credits, tr.tag_value
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
  LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
    ON wmh.warehouse_id = tr.object_id
   AND tr.domain = 'WAREHOUSE'
   AND tr.tag_name = 'COST_CENTER'
  WHERE wmh.start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND wmh.end_time < CURRENT_DATE()
    AND wmh.warehouse_id > 0
)
SELECT COALESCE(tag_value, 'UNTAGGED_RESOURCE') AS bucket,
       ROUND(SUM(credits), 1)                   AS credits,
       ROUND(100 * SUM(credits)
         / SUM(SUM(credits)) OVER (), 1)        AS pct_of_wh
FROM tagged
GROUP BY 1
ORDER BY credits DESC;

-- Shared warehouse: spread the whole bill pro-rata by attributed use.
WITH wh AS (
  SELECT SUM(credits_used_compute) AS bill
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
  WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE())
    AND end_time < CURRENT_DATE()
),
u AS (
  SELECT user_name, SUM(credits_attributed_compute) AS credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
  WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE())
    AND start_time < CURRENT_DATE()
  GROUP BY 1
)
SELECT u.user_name,
       ROUND(u.credits / NULLIF(SUM(u.credits) OVER (), 0)
         * wh.bill, 2) AS attributed_credits
FROM u CROSS JOIN wh
ORDER BY attributed_credits DESC;

-- Cost per active user-day: stable, comparable, hard to game.
WITH per_user AS (
  SELECT user_name,
         SUM(credits_attributed_compute) AS credits,
         COUNT(DISTINCT DATE_TRUNC('day', start_time)) AS days
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
  WHERE start_time >= DATE_TRUNC('month', DATEADD('month', -1,
                          CURRENT_DATE()))
    AND start_time <  DATE_TRUNC('month', CURRENT_DATE())
  GROUP BY 1
)
SELECT user_name,
       ROUND(credits, 4)                  AS credits_month,
       days                               AS active_days,
       ROUND(credits / NULLIF(days, 0), 6) AS credits_per_day
FROM per_user
ORDER BY credits DESC;

CREATE TAG cost_management.tags.cost_center
  ALLOWED_VALUES 'finance', 'marketing', 'engineering';

-- Billed platform credits by service, last complete UTC month.
SELECT service_type,
       ROUND(SUM(credits_billed), 1) AS billed_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATE_TRUNC('month', DATEADD('month', -1,
                        CURRENT_DATE()))
  AND usage_date <  DATE_TRUNC('month', CURRENT_DATE())
GROUP BY 1
ORDER BY billed_credits DESC;
