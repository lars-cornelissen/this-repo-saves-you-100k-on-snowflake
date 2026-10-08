-- Serverless Features and Budgets
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER SESSION SET TIMEZONE = UTC;

SELECT
    CASE
        WHEN service_type IN ('WAREHOUSE_METERING',
                              'WAREHOUSE_METERING_READER')
            THEN 'governed by resource monitors'
        ELSE 'NOT governed by resource monitors'
    END                 AS governability,
    service_type,
    SUM(credits_used)   AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1, credits_30d DESC;

SELECT
    service_type,
    SUM(credits_used) AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND service_type <> 'WAREHOUSE_METERING'
  AND service_type <> 'WAREHOUSE_METERING_READER'
GROUP BY 1
ORDER BY 2 DESC;

SELECT
    table_name,
    SUM(credits_used::NUMBER) AS mv_credits_30d,
    COUNT(*)                  AS refreshes
FROM SNOWFLAKE.ACCOUNT_USAGE.MATERIALIZED_VIEW_REFRESH_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 2 DESC;

SELECT
    task_name,
    SUM(credits_used::NUMBER) AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND service_type ILIKE '%SERVERLESS_TASK%'
GROUP BY 1
ORDER BY 2 DESC;

ALTER TASK my_db.ops.load_orders
  SET WHEN SYSTEM$STREAM_HAS_DATA('my_db.ops.orders_stream');

ALTER COMPUTE POOL my_pool SET AUTO_SUSPEND_SECS = 300;
ALTER COMPUTE POOL my_pool SET MIN_NODES = 1;

CREATE SNOWFLAKE.CORE.BUDGET my_db.admin.serverless_budget();

CALL my_db.admin.serverless_budget!SET_SPENDING_LIMIT(5000);

CALL my_db.admin.serverless_budget!ADD_RESOURCE(
    SYSTEM$REFERENCE('COMPUTE_POOL', 'my_pool'));

CALL my_db.admin.serverless_budget!SET_NOTIFICATION_THRESHOLD(75);

SELECT
    DATE_TRUNC('month', start_time) AS month,
    ROUND(100 * SUM(IFF(service_type <> 'WAREHOUSE_METERING',
            credits_used, 0))
        / NULLIF(SUM(credits_used), 0), 1) AS serverless_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('month', -6, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;
