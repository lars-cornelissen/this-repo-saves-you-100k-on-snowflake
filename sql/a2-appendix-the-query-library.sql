-- Appendix: The Query Library
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER SESSION SET TIMEZONE = UTC;

SELECT warehouse_name,
       ROUND(SUM(credits_used_compute)
             - SUM(credits_attributed_compute_queries), 2)
         AS idle_credits,
       ROUND(SUM(credits_used_compute), 2) AS compute_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  AND end_time   <  CURRENT_DATE()
GROUP BY warehouse_name
HAVING idle_credits > 0
ORDER BY idle_credits DESC;

SHOW WAREHOUSES
  ->> SELECT "name" AS warehouse_name,
             "size" AS warehouse_size,
             "owner" AS owner,
             IFNULL("auto_suspend", 0) AS auto_suspend,
             "auto_resume" AS auto_resume,
             "min_cluster_count" AS min_clusters,
             "max_cluster_count" AS max_clusters,
             "resource_monitor" AS resource_monitor
        FROM $1
        WHERE IFNULL("auto_suspend", 0) = 0
           OR "auto_resume" = 'false'
           OR IFNULL("auto_suspend", 0) < 60
           OR IFNULL("auto_suspend", 0) % 30 <> 0
           OR "min_cluster_count" = "max_cluster_count";

WITH load AS (
  SELECT warehouse_name,
         AVG(avg_running) AS avg_running_load,
         AVG(avg_queued_load) AS avg_queued_load
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
  WHERE start_time >= DATEADD('day', -14, CURRENT_TIMESTAMP())
  GROUP BY 1),
meter AS (
  SELECT warehouse_name,
         SUM(credits_used_compute) AS compute_credits,
         SUM(credits_used_compute
             - credits_attributed_compute_queries) AS idle_credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    AND warehouse_id > 0
  GROUP BY 1)
SELECT l.warehouse_name,
       ROUND(l.avg_running_load, 3) AS avg_running_load,
       ROUND(l.avg_queued_load, 3)  AS avg_queued_load,
       ROUND(m.compute_credits, 2)  AS compute_credits,
       ROUND(m.idle_credits, 2)     AS idle_credits
FROM load l LEFT JOIN meter m USING (warehouse_name)
WHERE l.avg_running_load < 1
ORDER BY m.idle_credits DESC;

SELECT query_id, SUBSTR(query_text, 1, 50) AS sample_sql,
       user_name, warehouse_name,
       bytes_spilled_to_local_storage  AS local_bytes,
       bytes_spilled_to_remote_storage AS remote_bytes
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -45, CURRENT_DATE())
  AND (bytes_spilled_to_local_storage > 0
    OR bytes_spilled_to_remote_storage > 0)
ORDER BY remote_bytes DESC, local_bytes DESC
LIMIT 10;

SELECT query_hash, warehouse_name,
       ROUND(MAX(total_elapsed_time) / 1000, 1) AS elapsed_sec,
       MAX(partitions_scanned) AS partitions_scanned,
       MAX(partitions_total)   AS partitions_total,
       ROUND(MAX(partitions_scanned)
             / NULLIF(MAX(partitions_total), 0), 3) AS scan_ratio,
       ROUND(MAX(partitions_scanned)
             / NULLIF(MAX(rows_written_to_result), 0), 1)
         AS partitions_per_row
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND error_code IS NULL
  AND query_type = 'SELECT'
  AND partitions_scanned > 100
  AND total_elapsed_time > 0
GROUP BY ALL
ORDER BY partitions_per_row DESC
LIMIT 50;

SELECT table_id, ANY_VALUE(table_name) AS table_name,
       SUM(num_scans) AS scans,
       SUM(partitions_scanned) AS scanned,
       SUM(partitions_pruned)  AS pruned,
       ROUND(SUM(partitions_pruned)
             / GREATEST(SUM(partitions_scanned
                            + partitions_pruned), 1), 3)
         AS pruning_ratio,
       ROUND(SUM(partitions_scanned)
             / NULLIF(SUM(num_scans), 0), 1) AS parts_per_scan
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_PRUNING_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY table_id
ORDER BY parts_per_scan DESC
LIMIT 20;

SELECT table_name, column_name, access_type,
       SUM(num_queries) AS queries,
       ROUND(SUM(rows_pruned)
             / NULLIF(SUM(rows_pruned + rows_scanned), 0), 3)
         AS pruning_ratio,
       ROUND(SUM(rows_scanned) / NULLIF(SUM(rows_matched), 0), 1)
         AS scan_per_match
FROM SNOWFLAKE.ACCOUNT_USAGE.COLUMN_QUERY_PRUNING_HISTORY
WHERE interval_start_time >= DATEADD('day', -14, CURRENT_TIMESTAMP())
GROUP BY table_name, column_name, access_type
HAVING SUM(num_queries) > 20
ORDER BY scan_per_match DESC NULLS LAST
LIMIT 50;

SELECT insight_type_id,
       COUNT(DISTINCT query_id) AS queries,
       ROUND(SUM(total_elapsed_time) / 1000 / 60, 1)
         AS total_minutes
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_INSIGHTS
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND insight_topic = 'TABLE_SCAN'
  AND is_opportunity = TRUE
  AND insight_type_id IN (
        'QUERY_INSIGHT_NO_FILTER_ON_TOP_OF_TABLE_SCAN',
        'QUERY_INSIGHT_INAPPLICABLE_FILTER_ON_TABLE_SCAN',
        'QUERY_INSIGHT_UNSELECTIVE_FILTER',
        'QUERY_INSIGHT_LIKE_WITH_LEADING_WILDCARD')
GROUP BY insight_type_id
ORDER BY total_minutes DESC;

SELECT query_hash, ANY_VALUE(query_text) AS sample_sql,
       COUNT(*) AS runs,
       ROUND(SUM(total_elapsed_time) / 1000 / 3600, 2)
         AS elapsed_hours,
       ROUND(SUM(bytes_scanned) / POWER(1024, 4), 3) AS tb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND warehouse_name = 'MY_WAREHOUSE'
GROUP BY query_hash
ORDER BY elapsed_hours DESC
LIMIT 100;

SELECT query_parameterized_hash,
       ANY_VALUE(query_text) AS sample_sql,
       ANY_VALUE(warehouse_name) AS wh,
       COUNT(*) AS runs,
       ROUND(SUM(credits_attributed_compute), 4) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY credits DESC
LIMIT 25;

SELECT warehouse_name, warehouse_size,
       COUNT(*) AS queries,
       ROUND(MEDIAN(execution_time) / 1000.0, 2) AS median_sec,
       ROUND(APPROX_PERCENTILE(execution_time, 0.95)
             / 1000.0, 2) AS p95_sec,
       ROUND(SUM(queued_overload_time) / 1000.0, 1)
         AS overload_queue_sec,
       ROUND(SUM(queued_provisioning_time) / 1000.0, 1)
         AS provisioning_queue_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
  AND execution_time > 0
GROUP BY 1, 2
ORDER BY median_sec DESC;

SELECT usage_date, service_type,
       SUM(credits_used) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD('month', -1, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY usage_date DESC, credits DESC;

SELECT DATE_TRUNC('day', start_time) AS usage_date,
       version, SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

WITH ach AS (
  SELECT table_id, ANY_VALUE(table_name) AS table_name,
         ANY_VALUE(version) AS version,
         SUM(credits_used) AS credits_30d,
         SUM(num_rows_reclustered) AS rows_30d
  FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  GROUP BY table_id
)
SELECT a.table_name, a.version, a.credits_30d,
       ROUND(a.rows_30d / GREATEST(t.row_count, 1), 2)
         AS recluster_amplification
FROM ach a
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TABLES t
  ON t.table_id = a.table_id
ORDER BY a.credits_30d DESC
LIMIT 50;

SELECT table_catalog, table_schema, table_name,
       clustering_key, auto_clustering_on, row_count, bytes
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
WHERE auto_clustering_on = 'ON'
ORDER BY bytes DESC;

ALTER SESSION SET TIMEZONE = UTC;

SELECT CASE
         WHEN service_type IN ('WAREHOUSE_METERING',
                               'WAREHOUSE_METERING_READER')
           THEN 'resource monitor covers'
         ELSE 'resource monitor CANNOT cover'
       END AS coverage,
       service_type,
       SUM(credits_used) AS credits_30d,
       ROUND(100 * SUM(credits_used)
             / SUM(SUM(credits_used)) OVER (), 1)
         AS pct_of_total
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY coverage, credits_30d DESC;

SELECT name, level, credit_quota, suspend, suspend_immediate, notify
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE suspend IS NULL
  AND suspend_immediate IS NULL
  AND (notify IS NULL OR ARRAY_SIZE(notify) = 0);

SELECT name AS monitor_name, level, credit_quota, used_credits,
       ROUND(used_credits / NULLIF(credit_quota, 0) * 100, 1)
         AS pct_used,
       remaining_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE credit_quota IS NOT NULL
ORDER BY pct_used DESC NULLS LAST;

SHOW WAREHOUSES
  ->> SELECT "name", "size", "owner", "resource_monitor"
        FROM $1
        WHERE "resource_monitor" IS NULL
        ORDER BY "name";

SELECT table_catalog || '.' || table_schema || '.' || table_name
         AS qualified_name,
       active_bytes, time_travel_bytes, failsafe_bytes,
       retained_for_clone_bytes,
       ROUND((active_bytes + time_travel_bytes + failsafe_bytes)
             / POWER(1024, 3), 3) AS billed_gib
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE deleted = FALSE
  AND table_dropped IS NULL
ORDER BY billed_gib DESC
LIMIT 50;

SELECT table_catalog || '.' || table_schema || '.' || table_name
         AS qualified_name,
       is_transient, active_bytes, time_travel_bytes,
       failsafe_bytes
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE deleted = FALSE
  AND is_transient = 'YES'
  AND failsafe_bytes > 0
ORDER BY failsafe_bytes DESC;

SELECT t.table_catalog || '.' || t.table_schema || '.'
         || t.table_name AS qualified_name,
       t.created,
       DATEDIFF(hour, t.created, CURRENT_TIMESTAMP()) AS age_hours,
       ROUND((m.active_bytes + m.time_travel_bytes
              + m.failsafe_bytes) / POWER(1024, 3), 3)
         AS billed_gib
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES t
JOIN SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS m
  ON m.table_name    = t.table_name
 AND m.table_schema  = t.table_schema
 AND m.table_catalog = t.table_catalog
 AND m.table_dropped IS NULL
WHERE t.table_type = 'TEMPORARY TABLE'
  AND t.deleted IS NULL
ORDER BY billed_gib DESC;

CREATE TABLE IF NOT EXISTS finops.warehouse_config_snapshot (
  captured_at TIMESTAMP_LTZ, name VARCHAR, size VARCHAR,
  state VARCHAR, auto_suspend NUMBER, auto_resume VARCHAR,
  min_clusters NUMBER, max_clusters NUMBER, owner VARCHAR,
  monitor VARCHAR
);

-- Run hourly from a task. Use RESULT_SCAN rather than the pipe
-- operator inside a task body.
SHOW WAREHOUSES;

INSERT INTO finops.warehouse_config_snapshot
  SELECT CURRENT_TIMESTAMP()::TIMESTAMP_LTZ,
         "name", "size", "state", IFNULL("auto_suspend", 0),
         "auto_resume", "min_cluster_count", "max_cluster_count",
         "owner", "resource_monitor"
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
