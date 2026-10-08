-- Resource Monitors and Quotas
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

CREATE OR REPLACE RESOURCE MONITOR analytics_monthly
  WITH CREDIT_QUOTA    = 960
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS
         ON 75 PERCENT DO NOTIFY
         ON 90 PERCENT DO SUSPEND
         ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE analytics_wh
  SET RESOURCE_MONITOR = analytics_monthly;

ALTER SESSION SET TIMEZONE = UTC;

SELECT
  CASE
    WHEN service_type IN ('WAREHOUSE_METERING',
                          'WAREHOUSE_METERING_READER')
      THEN 'monitor can govern'
    ELSE 'monitor CANNOT govern'
  END                              AS coverage,
  service_type,
  ROUND(SUM(credits_used), 1)      AS credits_30d,
  ROUND(100 * SUM(credits_used)
    / SUM(SUM(credits_used)) OVER (), 1) AS pct_of_total
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY coverage, credits_30d DESC;

SELECT name, size, state, resource_monitor
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES
WHERE deleted IS NULL
  AND resource_monitor IS NULL
ORDER BY name;

SELECT name, credit_quota, frequency, created
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE level IS NULL
ORDER BY created DESC;

SELECT name, level, credit_quota, suspend, suspend_immediate
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE suspend IS NULL
  AND suspend_immediate IS NULL
  AND (notify IS NULL OR ARRAY_SIZE(notify) = 0);

ALTER SESSION SET TIMEZONE = UTC;

SELECT
  DATE_TRUNC('day', start_time)            AS day,
  ROUND(SUM(credits_used_compute), 1)      AS warehouse_credits,
  ROUND(SUM(credits_used_cloud_services), 1)
                                           AS cloud_svc_credits,
  ROUND(SUM(credits_used), 1)              AS monitor_counter
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;

SHOW PARAMETERS IN ACCOUNT
  ->> SELECT "key", "value", "default", "level"
        FROM $1
        WHERE "key" IN (
          'STATEMENT_TIMEOUT_IN_SECONDS',
          'STATEMENT_QUEUED_TIMEOUT_IN_SECONDS',
          'ABORT_DETACHED_QUERY',
          'USE_CACHED_RESULT',
          'SUSPEND_TASK_AFTER_NUM_FAILURES',
          'TASK_AUTO_RETRY_ATTEMPTS',
          'SUSPEND_ALERT_AFTER_NUM_FAILURES'
        )
        ORDER BY "key";

SHOW WAREHOUSES
  ->> SELECT "name", "size", "auto_suspend", "auto_resume",
             "resource_monitor", "scaling_policy",
             "query_acceleration_max_scale_factor"
        FROM $1
        ORDER BY "name";

-- Production: notify loudly, do not suspend
CREATE OR REPLACE RESOURCE MONITOR prod_rm
  WITH CREDIT_QUOTA    = 5000
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS
         ON 50 PERCENT DO NOTIFY
         ON 75 PERCENT DO NOTIFY
         ON 100 PERCENT DO NOTIFY;

-- Non-production: suspend, and mean it
CREATE OR REPLACE RESOURCE MONITOR nonprod_rm
  WITH CREDIT_QUOTA    = 500
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS
         ON 75 PERCENT DO NOTIFY
         ON 90 PERCENT DO SUSPEND
         ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE analytics_prod_wh  SET RESOURCE_MONITOR = prod_rm;
ALTER WAREHOUSE etl_nightly_wh     SET RESOURCE_MONITOR = prod_batch_rm;
ALTER WAREHOUSE analyst_sandbox_wh SET RESOURCE_MONITOR = nonprod_rm;

SELECT
  COUNT(*)                                 AS warehouses,
  COUNT(resource_monitor)                  AS monitored,
  SUM(IFF(resource_monitor IS NULL, 1, 0)) AS unmonitored
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES
WHERE deleted IS NULL;

SELECT timestamp, warehouse_name, event_name, event_reason
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY
WHERE timestamp >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND event_name = 'RESOURCE_MONITOR_SUSPEND'
ORDER BY timestamp DESC;
