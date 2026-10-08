-- Measuring Before You Cut
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

CREATE TABLE IF NOT EXISTS cost_mgmt.raw.warehouse_hourly (
  start_time                         TIMESTAMP_LTZ,
  end_time                           TIMESTAMP_LTZ,
  warehouse_id                       NUMBER,
  warehouse_name                     VARCHAR,
  credits_used_compute               NUMBER(38,10),
  credits_used_cloud_services        NUMBER(38,10),
  credits_attributed_compute_queries NUMBER(38,10),
  _loaded_on                         TIMESTAMP_LTZ
    DEFAULT CURRENT_TIMESTAMP()
);

ALTER SESSION SET TIMEZONE = UTC;

DELETE FROM cost_mgmt.raw.warehouse_hourly
WHERE start_time >= DATEADD('day', -3, CURRENT_DATE());

INSERT INTO cost_mgmt.raw.warehouse_hourly
  (start_time, end_time, warehouse_id, warehouse_name,
   credits_used_compute, credits_used_cloud_services,
   credits_attributed_compute_queries)
SELECT
  start_time, end_time, warehouse_id, warehouse_name,
  credits_used_compute, credits_used_cloud_services,
  credits_attributed_compute_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -3, CURRENT_DATE())
  AND end_time <  CURRENT_DATE()
  AND warehouse_id > 0;

ALTER SESSION SET TIMEZONE = UTC;

SELECT
  ROUND(a.credits, 1)             AS source_credits,
  ROUND(m.credits, 1)             AS mart_credits,
  ROUND(a.credits - m.credits, 1) AS variance
FROM (
  SELECT SUM(credits_used_compute) AS credits
  FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND end_time <  CURRENT_DATE()
    AND warehouse_id > 0
) a
CROSS JOIN (
  SELECT SUM(credits_used_compute) AS credits
  FROM cost_mgmt.raw.warehouse_hourly
  WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
    AND end_time <  CURRENT_DATE()
) m;

ALTER SESSION SET TIMEZONE = UTC;

SELECT
  ROUND(SUM(credits_used_compute), 1)    AS compute_used,
  ROUND(SUM(credits_used_cloud_services), 1) AS cloud_used,
  ROUND(SUM(credits_adjustment_cloud_services), 1)
    AS adjustment,
  ROUND(SUM(credits_billed), 1)          AS billed
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD('month', -1,
                     DATE_TRUNC('month', CURRENT_DATE()))
  AND usage_date <  DATE_TRUNC('month', CURRENT_DATE());

CREATE TABLE IF NOT EXISTS cost_mgmt.mart.warehouse_cost_daily (
  usage_date         DATE,
  warehouse_id       NUMBER,
  warehouse_name     VARCHAR,
  cost_center        VARCHAR,
  credits_compute    NUMBER(38,10),
  credits_cloud_svc  NUMBER(38,10),
  credits_attributed NUMBER(38,10),
  credits_idle       NUMBER(38,10)
);

INSERT INTO cost_mgmt.mart.warehouse_cost_daily
SELECT
  DATE(start_time)                              AS usage_date,
  warehouse_id,
  MAX(warehouse_name)                           AS warehouse_name,
  'untagged'                                    AS cost_center,
  SUM(credits_used_compute)                     AS credits_compute,
  SUM(credits_used_cloud_services)              AS credits_cloud_svc,
  SUM(credits_attributed_compute_queries)       AS credits_attributed,
  SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries)   AS credits_idle
FROM cost_mgmt.raw.warehouse_hourly
WHERE start_time >= DATEADD('day', -3, CURRENT_DATE())
GROUP BY 1, 2
HAVING SUM(credits_used_compute) > 0;

-- Tiles 2 to 5: idle, multiplier, untagged share, warehouse count.
SELECT
  COUNT(DISTINCT warehouse_id)             AS warehouses,
  ROUND(SUM(credits_compute), 1)           AS compute_credits,
  ROUND(SUM(credits_idle), 1)              AS idle_credits,
  ROUND(100 * SUM(credits_idle)
    / NULLIF(SUM(credits_compute), 0), 1)  AS idle_pct,
  ROUND(SUM(credits_compute)
    / NULLIF(SUM(credits_attributed), 0), 2) AS idle_multiplier,
  ROUND(100 * SUM(IFF(cost_center = 'untagged',
      credits_compute, 0))
    / NULLIF(SUM(credits_compute), 0), 1)  AS untagged_pct
FROM cost_mgmt.mart.warehouse_cost_daily
WHERE usage_date >= DATE_TRUNC('month', CURRENT_DATE());

-- Tile 6: storage by state, in tebibytes.
SELECT
  ROUND(SUM(active_bytes) / 1099511627776, 1)      AS active_tib,
  ROUND(SUM(time_travel_bytes) / 1099511627776, 1) AS tt_tib,
  ROUND(SUM(failsafe_bytes) / 1099511627776, 1)    AS failsafe_tib,
  ROUND(SUM(retained_for_clone_bytes)
    / 1099511627776, 1)                            AS clone_tib
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS;

SELECT
  DATE_TRUNC('month', start_time)  AS month,
  ROUND(SUM(credits_used_compute), 1) AS compute_credits,
  ROUND(SUM(credits_used_compute)
    - SUM(credits_attributed_compute_queries), 1) AS idle_credits,
  ROUND(SUM(credits_used_compute)
    / NULLIF(SUM(credits_attributed_compute_queries), 0), 2)
    AS idle_multiplier
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('month', -12, CURRENT_DATE())
  AND end_time <  CURRENT_DATE()
  AND warehouse_id > 0
GROUP BY 1
ORDER BY 1;
