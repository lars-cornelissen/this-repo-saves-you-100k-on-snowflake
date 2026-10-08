-- Multi-Cluster, Concurrency and the Cost of Scaling Out
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SHOW WAREHOUSES
  ->> SELECT "name", "state", "size", "min_cluster_count",
             "max_cluster_count", "scaling_policy",
             "auto_suspend", "enable_query_acceleration",
             "query_acceleration_max_scale_factor"
        FROM $1
       WHERE "min_cluster_count" = "max_cluster_count"
         AND "max_cluster_count" > 1
       ORDER BY "max_cluster_count" DESC, "name";

SHOW WAREHOUSES
  ->> SELECT "name", "size", "max_cluster_count",
             "enable_query_acceleration",
             "query_acceleration_max_scale_factor"
        FROM $1
       WHERE "enable_query_acceleration" = TRUE
         AND "query_acceleration_max_scale_factor" = 2
         AND "max_cluster_count" > 1
       ORDER BY "name";

SELECT warehouse_name,
  COUNT(*) AS queries,
  MAX(cluster_number) AS max_cluster_used,
  COUNT_IF(cluster_number > 1) AS queries_on_extra_clusters
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
  AND cluster_number IS NOT NULL
GROUP BY 1
ORDER BY queries DESC;

SELECT warehouse_name,
  ROUND(SUM(credits_used_compute), 2) AS total_credits,
  ROUND(SUM(credits_used_compute) / (4.0 * COUNT(*)), 3)
    AS avg_clusters_running
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'MY_MCW'
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1;

SELECT warehouse_name,
  ROUND(SUM(queued_overload_time) / 3600000.0, 2)
    AS overload_hours,
  ROUND(SUM(queued_provisioning_time) / 3600000.0, 2)
    AS provisioning_hours,
  ROUND(SUM(transaction_blocked_time) / 3600000.0, 2)
    AS blocked_hours
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
GROUP BY warehouse_name
HAVING SUM(queued_overload_time) > 0
    OR SUM(queued_provisioning_time) > 0
    OR SUM(transaction_blocked_time) > 0
ORDER BY overload_hours DESC;

ALTER WAREHOUSE bi_mcw SET
  MAX_CLUSTER_COUNT = 4
  MIN_CLUSTER_COUNT = 1
  SCALING_POLICY    = 'ECONOMY'
  QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2;

SELECT warehouse_name,
  ROUND(SUM(credits_used_compute), 2) AS credits,
  ROUND(SUM(credits_used_compute) / (4.0 * COUNT(*)), 3)
    AS avg_clusters
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND warehouse_id > 0
GROUP BY 1
ORDER BY credits DESC;
