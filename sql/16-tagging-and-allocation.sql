-- Tagging and Allocation
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER SESSION SET QUERY_TAG = 'APP=dbt;COST_CENTER=finance;ENV=prod';

ALTER SESSION SET TIMEZONE = UTC;

SELECT
    DATE_TRUNC('month', start_time) AS month,
    ROUND(SUM(credits_used_compute)
        / NULLIF(SUM(credits_attributed_compute_queries), 0), 2)
        AS idle_multiplier,
    SUM(credits_used_compute)
      - SUM(credits_attributed_compute_queries)
        AS unattributed_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('month', -6, CURRENT_TIMESTAMP())
  AND warehouse_id > 0
GROUP BY 1
ORDER BY 1 DESC;

SELECT
    wmh.warehouse_name,
    SUM(wmh.credits_used_compute) AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
       ON tr.object_id = wmh.warehouse_id
      AND tr.domain    = 'WAREHOUSE'
      AND tr.tag_name  = 'COST_CENTER'
WHERE wmh.start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND wmh.warehouse_id > 0
  AND tr.object_id IS NULL
GROUP BY 1
ORDER BY 2 DESC;

WITH wh AS (
    SELECT
        wmh.warehouse_id,
        SUM(wmh.credits_used_compute) AS credits,
        MAX(tr.tag_value)             AS cost_center
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
           ON tr.object_id = wmh.warehouse_id
          AND tr.domain    = 'WAREHOUSE'
          AND tr.tag_name  = 'COST_CENTER'
    WHERE wmh.start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
      AND wmh.warehouse_id > 0
    GROUP BY 1
)
SELECT
    COUNT(*)                    AS warehouses,
    COUNT(cost_center)          AS tagged_warehouses,
    ROUND(100 * SUM(IFF(cost_center IS NOT NULL, credits, 0))
          / NULLIF(SUM(credits), 0), 1) AS pct_credits_tagged
FROM wh;

SELECT
    service_type,
    SUM(credits_used) AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND service_type <> 'WAREHOUSE_METERING'
GROUP BY 1
ORDER BY 2 DESC;

SELECT
    user_name,
    COUNT(*) AS queries,
    ROUND(100 * COUNT(query_tag) / NULLIF(COUNT(*), 0), 1)
        AS pct_tagged
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1
HAVING COUNT(*) > 100
ORDER BY pct_tagged ASC;

CREATE TABLE IF NOT EXISTS cost_mgmt.mart.wh_cost_daily (
    usage_date         DATE,
    warehouse_id       NUMBER,
    warehouse_name     VARCHAR,
    cost_center        VARCHAR,   -- resolved at load, frozen
    tag_apply_method   VARCHAR,
    credits_compute    NUMBER(38,10),
    credits_idle       NUMBER(38,10)
);

MERGE INTO cost_mgmt.mart.wh_cost_daily t
USING (
    SELECT
        DATE(wmh.start_time)                       AS usage_date,
        wmh.warehouse_id,
        MAX(wmh.warehouse_name)                    AS warehouse_name,
        COALESCE(MAX(tr.tag_value), 'untagged')    AS cost_center,
        MAX(tr.apply_method)                       AS tag_apply_method,
        SUM(wmh.credits_used_compute)              AS credits_compute,
        SUM(wmh.credits_used_compute)
          - SUM(wmh.credits_attributed_compute_queries)
                                                   AS credits_idle
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
           ON tr.object_id = wmh.warehouse_id
          AND tr.domain    = 'WAREHOUSE'
          AND tr.tag_name  = 'COST_CENTER'
    WHERE wmh.start_time >= DATEADD('day', -3, CURRENT_TIMESTAMP())
      AND wmh.warehouse_id > 0
    GROUP BY 1, 2
) s
ON  t.usage_date   = s.usage_date
AND t.warehouse_id = s.warehouse_id
WHEN MATCHED THEN UPDATE SET
    cost_center     = s.cost_center,
    credits_compute = s.credits_compute,
    credits_idle    = s.credits_idle;

CREATE TAG IF NOT EXISTS cost_mgmt.tags.cost_center
  ALLOWED_VALUES 'finance', 'marketing', 'engineering',
                 'product', 'platform';

ALTER WAREHOUSE analytics_wh
  SET TAG cost_mgmt.tags.cost_center = 'engineering';

WITH per_query AS (
    SELECT user_name,
           SUM(credits_attributed_compute) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
    WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY user_name
),
totals AS (
    SELECT SUM(credits) AS all_credits FROM per_query
),
wh AS (
    SELECT SUM(credits_used_compute) AS compute_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
      AND warehouse_id > 0
)
SELECT
    p.user_name,
    p.credits AS attributed,
    ROUND(p.credits / t.all_credits * w.compute_credits, 1)
        AS allocated_incl_idle
FROM per_query p
CROSS JOIN totals t
CROSS JOIN wh w
ORDER BY allocated_incl_idle DESC;

-- dbt profile or pre-hook
ALTER SESSION SET QUERY_TAG = 'APP=dbt;COST_CENTER=finance';
-- Airflow connection or on-execute callback
ALTER SESSION SET QUERY_TAG = 'APP=airflow;DAG=daily_revenue';

SELECT
    b.billed_credits,
    a.allocated_credits,
    ROUND(100 * a.allocated_credits
          / NULLIF(b.billed_credits, 0), 2) AS allocated_pct
FROM (SELECT SUM(credits_billed) AS billed_credits
      FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
      WHERE usage_date >= DATE_TRUNC('month',
              DATEADD('month', -1, CURRENT_DATE()))
        AND usage_date <  DATE_TRUNC('month', CURRENT_DATE())) b
CROSS JOIN
     (SELECT SUM(credits_compute) AS allocated_credits
      FROM cost_mgmt.mart.wh_cost_daily
      WHERE usage_date >= DATE_TRUNC('month',
              DATEADD('month', -1, CURRENT_DATE()))
        AND usage_date <  DATE_TRUNC('month', CURRENT_DATE())) a;

SELECT
    apply_method,
    COUNT(*) AS associations
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_name = 'COST_CENTER'
GROUP BY 1
ORDER BY 2 DESC;

SELECT object_name, tag_name
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_value = 'CONFLICT';
