-- Reading the Query Profile
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER SESSION SET TIMEZONE = UTC;

SELECT service_type,
       ROUND(SUM(credits_used), 1) AS credits_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1
ORDER BY credits_30d DESC;

SELECT
  warehouse_name,
  ROUND(SUM(credits_used_compute), 1) AS compute_credits,
  ROUND(SUM(credits_attributed_compute_queries), 1)
                                      AS attributed,
  ROUND(SUM(credits_used_compute)
      - SUM(credits_attributed_compute_queries), 1)
                                      AS idle_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('month', -1, CURRENT_DATE())
GROUP BY 1
ORDER BY compute_credits DESC;

SELECT
  COALESCE(NULLIF(query_tag, ''), 'untagged') AS tag,
  ROUND(SUM(credits_attributed_compute), 1)   AS compute_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD('month', -1, CURRENT_DATE())
GROUP BY 1
ORDER BY compute_credits DESC;

SELECT
  query_parameterized_hash,
  COUNT(*)                                   AS runs,
  ROUND(SUM(credits_attributed_compute), 1)  AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD('month', -1, CURRENT_DATE())
  AND start_time < CURRENT_DATE()
GROUP BY 1
ORDER BY credits DESC
LIMIT 20;

SELECT
  query_id, warehouse_size, start_time,
  total_elapsed_time / 1000      AS elapsed_s,
  execution_time / 1000          AS exec_s,
  compilation_time / 1000        AS compile_s,
  queued_provisioning_time / 1000 AS q_provision_s,
  queued_overload_time / 1000     AS q_overload_s,
  transaction_blocked_time / 1000 AS blocked_s,
  bytes_scanned,
  percentage_scanned_from_cache,
  partitions_scanned,
  partitions_total,
  bytes_spilled_to_local_storage,
  bytes_spilled_to_remote_storage
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_parameterized_hash = '<hash>'
  AND start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY start_time DESC
LIMIT 50;

SELECT
  step_id,
  operator_id,
  operator_type,
  operator_statistics:input_rows::NUMBER       AS input_rows,
  operator_statistics:output_rows::NUMBER      AS output_rows,
  operator_statistics:pruning:partitions_scanned::NUMBER
                                               AS parts_scanned,
  operator_statistics:pruning:partitions_total::NUMBER
                                               AS parts_total,
  operator_statistics:spilling:bytes_spilled_local_storage::NUMBER
                                               AS spill_local,
  operator_statistics:spilling:bytes_spilled_remote_storage::NUMBER
                                               AS spill_remote,
  execution_time_breakdown:overall_percentage::FLOAT AS pct_exec,
  execution_time_breakdown:remote_disk_io::FLOAT     AS remote_io
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id>'))
ORDER BY pct_exec DESC;

SELECT
  warehouse_size,
  COUNT(*)                          AS runs,
  MEDIAN(execution_time) / 1000.0   AS median_exec_s,
  MEDIAN(bytes_spilled_to_local_storage)  AS median_local_spill,
  MEDIAN(bytes_spilled_to_remote_storage) AS median_remote_spill
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_hash = '<your_query_hash>'
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
GROUP BY warehouse_size
ORDER BY median_exec_s;

SELECT
  TO_DATE(start_time)         AS day,
  warehouse_name,
  ROUND(SUM(avg_running), 2)  AS running,
  ROUND(SUM(avg_queued_load), 2) AS queued,
  ROUND(SUM(avg_queued_provisioning), 2) AS provisioning,
  ROUND(SUM(avg_blocked), 2)  AS blocked
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY day DESC, warehouse_name;
