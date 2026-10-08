-- Appendix: The Synthetic Account
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

USE ROLE ACCOUNTADMIN;

-- The correct small warehouse: a 60-second suspend, on the poll grid.
CREATE OR REPLACE WAREHOUSE wh_xs_demo
  WAREHOUSE_SIZE      = XSMALL
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ch 4/5: the right-sized shape';

-- The fossil: suspension disabled entirely. Never sleeps.
CREATE OR REPLACE WAREHOUSE wh_idle_demo
  WAREHOUSE_SIZE      = SMALL
  AUTO_SUSPEND        = 0
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ch 4/6/8: the configuration fossil';

-- Maximized mode: min == max above one. Bills full width.
CREATE OR REPLACE WAREHOUSE wh_max_demo
  WAREHOUSE_SIZE      = MEDIUM
  MIN_CLUSTER_COUNT   = 3
  MAX_CLUSTER_COUNT   = 3
  AUTO_SUSPEND        = 600
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ch 6: Maximized mode arithmetic';

-- The dashboard warehouse: default suspend, the value nobody set.
CREATE OR REPLACE WAREHOUSE wh_bi_demo
  WAREHOUSE_SIZE      = MEDIUM
  AUTO_SUSPEND        = 600
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ch 7: the BI warehouse and its cache';

-- The big one, for spill and clustering arithmetic.
CREATE OR REPLACE WAREHOUSE wh_big_demo
  WAREHOUSE_SIZE      = XLARGE
  AUTO_SUSPEND        = 300
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ch 5/10: spill and downsize A/B';

-- Auto-scale, with the minimum at the default of one.
CREATE OR REPLACE WAREHOUSE wh_scale_demo
  WAREHOUSE_SIZE      = MEDIUM
  MIN_CLUSTER_COUNT   = 1
  MAX_CLUSTER_COUNT   = 4
  SCALING_POLICY      = ECONOMY
  AUTO_SUSPEND        = 300
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ch 6: auto-scale with ECONOMY';

CREATE OR REPLACE DATABASE demo_db
  COMMENT = 'Ch 13: permanent, with Fail-safe';

CREATE OR REPLACE TRANSIENT DATABASE demo_transient_db
  COMMENT = 'Ch 13: transient, no Fail-safe';

CREATE SCHEMA demo_db.raw;
CREATE SCHEMA demo_db.marts;
CREATE SCHEMA demo_db.scratch;
CREATE SCHEMA demo_transient_db.staging;

CREATE OR REPLACE TAG demo_db.cost_center;
CREATE OR REPLACE TAG demo_db.environment;
CREATE OR REPLACE TAG demo_db.owner_team;

ALTER WAREHOUSE wh_bi_demo
  SET TAG demo_db.cost_center  = 'marketing',
          demo_db.environment  = 'prod';

ALTER WAREHOUSE wh_idle_demo
  SET TAG demo_db.cost_center  = 'data-platform',
          demo_db.environment  = 'prod';

ALTER DATABASE demo_db
  SET TAG demo_db.owner_team = 'analytics-engineering';

-- Permanent: the fact table. Full Time Travel and 7 days of
-- Fail-safe, which is not configurable on a permanent table.
CREATE OR REPLACE TABLE demo_db.raw.events (
  event_ts   TIMESTAMP_NTZ NOT NULL,
  device_id  VARCHAR(64)   NOT NULL,
  fleet_code VARCHAR(8)    NOT NULL,
  metric     VARCHAR(32)   NOT NULL,
  value      NUMBER(12,4)
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  COMMENT = 'Ch 11/12: the clustered fact table';

-- Permanent dimension, the small table the fact table joins to.
CREATE OR REPLACE TABLE demo_db.raw.device_registry (
  device_id  VARCHAR(64) NOT NULL,
  fleet_code VARCHAR(8)  NOT NULL,
  model      VARCHAR(32),
  in_service DATE
);

-- Transient: same shape, no Fail-safe, shorter recovery.
CREATE OR REPLACE TRANSIENT TABLE
  demo_transient_db.staging.events_stage (
  event_ts   TIMESTAMP_NTZ,
  device_id  VARCHAR(64),
  metric     VARCHAR(32),
  value      NUMBER(12,4)
)
  DATA_RETENTION_TIME_IN_DAYS = 0
  COMMENT = 'Ch 13: transient, no Fail-safe';

-- Semi-structured, for the VARIANT path expressions.
CREATE OR REPLACE TRANSIENT TABLE demo_db.raw.events_raw (
  event_ts TIMESTAMP_NTZ,
  payload  VARIANT
);

-- The dashboard mart, small enough to keep a warehouse cache warm.
CREATE OR REPLACE TRANSIENT TABLE demo_db.marts.daily_device_kpi (
  day          DATE,
  fleet_code   VARCHAR(8),
  device_count NUMBER,
  avg_value    NUMBER(12,4),
  events       NUMBER
);

-- Temporary: exists for one session and then stops existing.
CREATE OR REPLACE TEMPORARY TABLE demo_db.scratch.session_work (
  query_id  VARCHAR(64),
  note      VARCHAR(200)
);

INSERT INTO demo_db.raw.events
  (event_ts, device_id, fleet_code, metric, value)
SELECT
  DATEADD('second', -SEQ4() * 3, CURRENT_TIMESTAMP()),
  'flt-a1b2c3d4-' || LPAD(MOD(SEQ4(), 4000)::STRING, 6, '0'),
  'flt-' || LPAD(MOD(SEQ4(), 9)::STRING, 2, '0'),
  'speed',
  UNIFORM(0, 120, RANDOM())::NUMBER(12,4)
FROM TABLE(GENERATOR(ROWCOUNT => 5000000));

INSERT INTO demo_db.raw.device_registry
  (device_id, fleet_code, model, in_service)
SELECT DISTINCT
  device_id,
  fleet_code,
  'model-' || MOD(HASH(device_id), 12)::STRING,
  DATEADD('day', -400, CURRENT_DATE())
FROM demo_db.raw.events;

INSERT INTO demo_db.marts.daily_device_kpi
SELECT
  TO_DATE(event_ts) AS day,
  fleet_code,
  COUNT(DISTINCT device_id),
  ROUND(AVG(value), 4),
  COUNT(*)
FROM demo_db.raw.events
GROUP BY 1, 2;

ALTER TABLE demo_db.raw.events
  CLUSTER BY (TO_DATE(event_ts), device_id);

SELECT SYSTEM$CLUSTERING_INFORMATION(
         'DEMO_DB.RAW.EVENTS');

CREATE OR REPLACE TEMPORARY TABLE demo_db.scratch.est_samples (
  run_no INT, payload VARIANT);

INSERT INTO demo_db.scratch.est_samples
SELECT SEQ4(),
       PARSE_JSON(SYSTEM$ESTIMATE_AUTOMATIC_CLUSTERING_COSTS(
         'DEMO_DB.RAW.EVENTS', '(TO_DATE(event_ts), device_id)'))
FROM TABLE(GENERATOR(ROWCOUNT => 5));

SELECT AVG(payload:initial:value::NUMBER(38,4))
         AS avg_initial_credits,
       AVG(payload:maintenance:value::NUMBER(38,4))
         AS avg_daily_maintenance_credits
FROM demo_db.scratch.est_samples;

-- The working monitor: a cascade, sized low, on the warehouses
-- that could actually run away.
CREATE OR REPLACE RESOURCE MONITOR monitor_demo_monthly
  WITH CREDIT_QUOTA    = 120
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS
         ON 75 PERCENT DO NOTIFY
         ON 90 PERCENT DO SUSPEND
         ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE wh_big_demo
  SET RESOURCE_MONITOR = monitor_demo_monthly;
ALTER WAREHOUSE wh_max_demo
  SET RESOURCE_MONITOR = monitor_demo_monthly;
ALTER WAREHOUSE wh_scale_demo
  SET RESOURCE_MONITOR = monitor_demo_monthly;
ALTER WAREHOUSE wh_bi_demo
  SET RESOURCE_MONITOR = monitor_demo_monthly;

-- The anti-pattern, reproduced: a monitor with no SUSPEND action
-- and a notification target nobody reads. It will appear in
-- SHOW RESOURCE MONITORS and it will prevent nothing.
CREATE OR REPLACE RESOURCE MONITOR monitor_demo_notify_only
  WITH CREDIT_QUOTA    = 50
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS
         ON 100 PERCENT DO NOTIFY;

-- Account-level monitors require NOTIFY_USERS to be NULL.
ALTER ACCOUNT SET RESOURCE_MONITOR = monitor_demo_notify_only;

-- Every warehouse, with the settings that decide its cost.
SHOW WAREHOUSES
  ->> SELECT "name", "size", IFNULL("auto_suspend", 0)
            AS auto_suspend, "min_cluster_count",
            "max_cluster_count", "resource_monitor"
        FROM $1
      ORDER BY "name";

-- Every monitor, with its triggers and its target list.
SHOW RESOURCE MONITORS;

-- The tags, and what they are attached to.
SELECT tag_name, tag_value, object_name, object_type
FROM TABLE(demo_db.information_schema.tag_references_all_columns(
       'DEMO_DB.RAW.EVENTS', 'TABLE'))
LIMIT 10;

USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET RESOURCE_MONITOR = NULL;

DROP DATABASE IF EXISTS demo_db;
DROP DATABASE IF EXISTS demo_transient_db;

DROP RESOURCE MONITOR IF EXISTS monitor_demo_monthly;
DROP RESOURCE MONITOR IF EXISTS monitor_demo_notify_only;

DROP WAREHOUSE IF EXISTS wh_xs_demo;
DROP WAREHOUSE IF EXISTS wh_idle_demo;
DROP WAREHOUSE IF EXISTS wh_max_demo;
DROP WAREHOUSE IF EXISTS wh_bi_demo;
DROP WAREHOUSE IF EXISTS wh_big_demo;
DROP WAREHOUSE IF EXISTS wh_scale_demo;
