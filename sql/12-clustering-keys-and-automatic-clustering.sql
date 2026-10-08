-- Clustering Keys and Automatic Clustering
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT DATE_TRUNC('day', start_time) AS usage_date,
       version,
       SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

SELECT SYSTEM$CLUSTERING_INFORMATION(
         'MY_DB.MY_SCHEMA.MY_TABLE');

WITH ach AS (
  SELECT table_id,
         ANY_VALUE(table_name) AS table_name,
         ANY_VALUE(version)    AS version,
         SUM(credits_used)     AS credits_30d,
         SUM(num_bytes_reclustered) AS bytes_30d,
         SUM(num_rows_reclustered)  AS rows_30d
  FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
  GROUP BY table_id
)
SELECT a.table_name,
       a.version,
       a.credits_30d,
       a.bytes_30d / POWER(1024, 3) AS gb_reclustered_30d,
       ROUND(a.rows_30d / GREATEST(t.row_count, 1), 2)
         AS recluster_amplification
FROM ach a
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TABLES t
  ON t.table_id = a.table_id
ORDER BY a.credits_30d DESC
LIMIT 50;

SELECT table_name,
       SUM(num_queries) AS queries_7d,
       SUM(partitions_scanned) / NULLIF(SUM(num_queries), 0)
         AS parts_scanned_per_query
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_QUERY_PRUNING_HISTORY
WHERE interval_start_time
        >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY table_name
ORDER BY queries_7d ASC
LIMIT 50;

CREATE OR REPLACE TEMPORARY TABLE est_samples (
  run_no INT, payload VARIANT);

INSERT INTO est_samples
SELECT seq4(),
       PARSE_JSON(SYSTEM$ESTIMATE_AUTOMATIC_CLUSTERING_COSTS(
         'MY_DB.MY_SCHEMA.MY_TABLE', '(order_date, tenant_id)'))
FROM TABLE(GENERATOR(ROWCOUNT => 10));

SELECT AVG(payload:initial:value::NUMBER(38,4))
         AS avg_initial_credits,
       AVG(payload:maintenance:value::NUMBER(38,4))
         AS avg_daily_maintenance_credits,
       COUNT_IF(payload:maintenance = PARSE_JSON('{}'))
         AS runs_without_maintenance_estimate
FROM est_samples;

SELECT t.table_name,
       t.clustering_key,
       t.auto_clustering_on,
       SUM(h.credits_used) AS credits_30d,
       SUM(h.num_rows_reclustered) AS rows_30d,
       t.row_count
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES t
JOIN SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY h
  ON h.table_id = t.table_id
WHERE h.start_time >= DATEADD('day', -30, CURRENT_DATE())
  AND t.deleted IS NULL
GROUP BY 1, 2, 3, 6
ORDER BY credits_30d DESC;
