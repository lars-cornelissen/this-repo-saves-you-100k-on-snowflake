-- Interlude: The Clustering Key That Cost More Than It Saved
-- From the book "This Book Saves You $100,000 a Year on Snowflake".

ALTER TABLE analytics.telemetry_events
  CLUSTER BY (TO_DATE(event_ts), device_id);

WHERE TO_DATE(event_ts) = CURRENT_DATE()

ALTER TABLE analytics.telemetry_events SUSPEND RECLUSTER;

CLUSTER BY LINEAR(TO_DATE(event_ts), device_id)
