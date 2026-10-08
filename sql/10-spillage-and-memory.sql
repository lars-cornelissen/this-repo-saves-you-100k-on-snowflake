-- Spillage and Memory
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT
  query_id,
  SUBSTR(query_text, 1, 60)  AS partial_query_text,
  warehouse_name,
  warehouse_size,
  start_time,
  total_elapsed_time / 1000.0 AS elapsed_seconds,
  bytes_spilled_to_local_storage,
  bytes_spilled_to_remote_storage,
  (bytes_spilled_to_local_storage
   + bytes_spilled_to_remote_storage) AS total_spilled_bytes
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
  AND (bytes_spilled_to_local_storage > 0
    OR bytes_spilled_to_remote_storage > 0)
ORDER BY total_spilled_bytes DESC
LIMIT 50;

SELECT
  query_id,
  warehouse_name,
  warehouse_size,
  total_elapsed_time / 1000.0 AS elapsed_seconds,
  CASE warehouse_size
    WHEN 'X-Small'  THEN 1   WHEN 'Small'    THEN 2
    WHEN 'Medium'   THEN 4   WHEN 'Large'    THEN 8
    WHEN 'X-Large'  THEN 16  WHEN '2X-Large' THEN 32
    WHEN '3X-Large' THEN 64  WHEN '4X-Large' THEN 128
  END                          AS credits_per_hour,
  ROUND((total_elapsed_time / 1000.0) / 3600.0
    * CASE warehouse_size
        WHEN 'X-Small'  THEN 1   WHEN 'Small'    THEN 2
        WHEN 'Medium'   THEN 4   WHEN 'Large'    THEN 8
        WHEN 'X-Large'  THEN 16  WHEN '2X-Large' THEN 32
        WHEN '3X-Large' THEN 64  WHEN '4X-Large' THEN 128
      END, 3)                  AS credits_this_run_est
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND (bytes_spilled_to_local_storage > 0
    OR bytes_spilled_to_remote_storage > 0)
ORDER BY credits_this_run_est DESC
LIMIT 50;

SELECT
  step_id,
  operator_id,
  operator_type,
  operator_statistics:spilling:bytes_spilled_local_storage::NUMBER
    AS spill_local,
  operator_statistics:spilling:bytes_spilled_remote_storage::NUMBER
    AS spill_remote,
  operator_statistics:input_rows::NUMBER  AS input_rows,
  operator_statistics:output_rows::NUMBER AS output_rows,
  ROUND(operator_statistics:output_rows::NUMBER
    / NULLIF(operator_statistics:input_rows::NUMBER, 0), 2)
    AS row_multiple
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id>'))
WHERE COALESCE(
    operator_statistics:spilling:bytes_spilled_local_storage::NUMBER, 0)
    > 0
   OR COALESCE(
    operator_statistics:spilling:bytes_spilled_remote_storage::NUMBER,
    0) > 0
ORDER BY spill_remote DESC NULLS LAST, spill_local DESC NULLS LAST;

SELECT
  DATE_TRUNC('week', start_time) AS wk,
  warehouse_name,
  COUNT(*)                       AS queries,
  COUNT_IF(bytes_spilled_to_local_storage > 0)
                                 AS spilled_local,
  COUNT_IF(bytes_spilled_to_remote_storage > 0)
                                 AS spilled_remote
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY wk DESC, spilled_remote DESC;

SELECT
  warehouse_size,
  COUNT(*)                            AS runs,
  ROUND(MEDIAN(execution_time) / 1000.0, 1)
                                      AS median_exec_s,
  MEDIAN(bytes_spilled_to_local_storage)  AS spill_local,
  MEDIAN(bytes_spilled_to_remote_storage) AS spill_remote
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_hash = '<your_query_hash>'
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
GROUP BY warehouse_size
ORDER BY median_exec_s;
