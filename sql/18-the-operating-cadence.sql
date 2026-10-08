-- The Operating Cadence
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

-- The inventory. Run it monthly and diff it against last month's.
SHOW WAREHOUSES
  ->> SELECT "name"              AS warehouse_name,
             "size"              AS size,
             "auto_suspend"      AS auto_suspend,
             "auto_resume"       AS auto_resume,
             "min_cluster_count" AS min_clusters,
             "max_cluster_count" AS max_clusters,
             "resource_monitor"  AS resource_monitor
        FROM $1
        ORDER BY "name";

-- The guardrails that bound a runaway query.
SHOW PARAMETERS LIKE 'STATEMENT_TIMEOUT_IN_SECONDS' IN ACCOUNT;
SHOW PARAMETERS LIKE 'STATEMENT_QUEUED_TIMEOUT_IN_SECONDS' IN ACCOUNT;
SHOW PARAMETERS LIKE 'ABORT_DETACHED_QUERY' IN ACCOUNT;

-- Warehouses with auto-suspend disabled. Documented query.
SHOW WAREHOUSES
  ->> SELECT "name" AS warehouse_name,
             "size" AS warehouse_size
        FROM $1
        WHERE IFNULL("auto_suspend", 0) = 0;

ALTER SESSION SET TIMEZONE = UTC;
SELECT service_type,
       ROUND(SUM(credits_billed), 2) AS credits_billed
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD('day', -7, CURRENT_DATE())
  AND usage_date <  CURRENT_DATE()
GROUP BY 1
ORDER BY credits_billed DESC;

-- Idle credits per warehouse. Keep the end_time fence.
SELECT
  (SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries)) AS idle_cost,
  warehouse_name
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('days', -10, CURRENT_DATE())
  AND end_time < CURRENT_DATE()
GROUP BY warehouse_name;

-- Quarterly sweep: which warehouses are sized above their load?
SELECT warehouse_name,
       ROUND(AVG(avg_running), 1)            AS avg_running,
       ROUND(AVG(avg_query_load_percent), 1) AS avg_load_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_DATE())
GROUP BY 1
ORDER BY avg_load_pct;

CREATE OR REPLACE TABLE finops.savings_backlog (
  id                NUMBER AUTOINCREMENT PRIMARY KEY,
  discovered_on     DATE    NOT NULL,
  title             VARCHAR NOT NULL,
  source            VARCHAR,   -- 'weekly' | 'insight' | 'audit'
  scope_object      VARCHAR,   -- the concrete object name
  symptom           VARCHAR,   -- the number that triggered it
  est_credits_month NUMBER,    -- an estimate, labelled as such
  est_basis         VARCHAR,   -- how you got the number. Not NULL
  effort            VARCHAR,   -- 'S' | 'M' | 'L'
  owner             VARCHAR NOT NULL,  -- a person, not a team
  status            VARCHAR NOT NULL,  -- 'proposed' | 'done'
  change_sql        VARCHAR,   -- the exact ALTER, for the change log
  baseline_credits_month NUMBER,   -- the measured before value
  measured_credits_month NUMBER,   -- the measured after value
  verified_on       DATE,
  reverted_reason   VARCHAR
);

SELECT status,
       COUNT(*)                          AS rows_n,
       ROUND(SUM(est_credits_month), 0)  AS est_credits,
       COUNT_IF(verified_on IS NOT NULL) AS verified,
       COUNT_IF(status = 'reverted')     AS reverted
FROM finops.savings_backlog
GROUP BY 1
ORDER BY est_credits DESC;
