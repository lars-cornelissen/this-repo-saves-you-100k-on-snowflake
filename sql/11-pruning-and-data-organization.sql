-- Pruning and Data Organization
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

SELECT query_hash,
       MAX(partitions_scanned) AS parts_scanned,
       MAX(partitions_total)   AS parts_total,
       ROUND(MAX(partitions_scanned)
         / NULLIF(MAX(rows_written_to_result), 0), 1)
         AS partitions_per_row
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND error_code IS NULL
  AND query_type = 'SELECT'
  AND partitions_scanned > 100
  AND rows_written_to_result > 0
GROUP BY query_hash
ORDER BY partitions_per_row DESC
LIMIT 50;

SELECT ANY_VALUE(table_name) AS table_name,
       SUM(num_scans) AS scans,
       SUM(partitions_scanned) AS scanned,
       SUM(partitions_pruned)  AS pruned,
       ROUND(SUM(partitions_pruned) / GREATEST(
         SUM(partitions_scanned + partitions_pruned), 1), 3)
         AS pruning_ratio,
       SUM(partitions_scanned) / NULLIF(SUM(num_scans), 0)
         AS parts_scanned_per_query
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_QUERY_PRUNING_HISTORY
WHERE interval_start_time
        >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY table_id
ORDER BY parts_scanned_per_query DESC
LIMIT 20;

SELECT table_name, column_name, access_type,
       SUM(num_queries) AS queries,
       ROUND(SUM(rows_pruned) / NULLIF(
         SUM(rows_pruned + rows_scanned), 0), 3) AS prune_ratio,
       ROUND(SUM(rows_scanned)
         / NULLIF(SUM(rows_matched), 0), 1)      AS scan_per_match
FROM SNOWFLAKE.ACCOUNT_USAGE.COLUMN_QUERY_PRUNING_HISTORY
WHERE interval_start_time
        >= DATEADD('day', -14, CURRENT_TIMESTAMP())
GROUP BY table_name, column_name, access_type
HAVING SUM(num_queries) > 20
ORDER BY scan_per_match DESC NULLS LAST
LIMIT 50;

SELECT insight_type_id,
       COUNT(DISTINCT query_id)            AS affected_queries,
       SUM(total_elapsed_time) / 1000 / 60 AS total_minutes
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_INSIGHTS
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND insight_topic = 'TABLE_SCAN'
  AND is_opportunity = TRUE
GROUP BY insight_type_id
ORDER BY total_minutes DESC;

SELECT COUNT(*) AS scan_insights_30d
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_INSIGHTS
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND insight_topic = 'TABLE_SCAN';

SELECT SUM(quantity), AVG(extendedprice), COUNT(*)
FROM lineitem
WHERE shipdate >= DATEADD('day', -90, TO_DATE('2023-01-01'));

-- Before: no partition can be pruned; every one is scanned.
WHERE TO_DATE(ordered_at) = CURRENT_DATE()

-- After: the range compares to the column's min/max metadata.
WHERE ordered_at >= CURRENT_DATE()
  AND ordered_at <  DATEADD('day', 1, CURRENT_DATE())

ALTER TABLE events
  ALTER COLUMN event_date SET DATA TYPE DATE
  USING TO_DATE(event_date);

SELECT DATE_TRUNC('week', start_time) AS week,
       insight_type_id,
       COUNT(DISTINCT query_id) AS queries
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_INSIGHTS
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
  AND insight_topic = 'TABLE_SCAN'
GROUP BY 1, 2
ORDER BY 1, 2;
