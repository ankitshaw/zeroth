-- ============================================================
-- Zeroth — Sample Iceberg Queries via Trino
-- ============================================================

-- 1. Create a schema in the Iceberg catalog
CREATE SCHEMA IF NOT EXISTS iceberg.demo;

-- 2. Create an Iceberg table with Parquet format
CREATE TABLE iceberg.demo.events (
    id          BIGINT,
    event_type  VARCHAR,
    user_id     BIGINT,
    payload     VARCHAR,
    city        VARCHAR,
    created_at  TIMESTAMP(6) WITH TIME ZONE
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['day(created_at)', 'city']
);

-- 3. Insert some sample data
INSERT INTO iceberg.demo.events VALUES
    (1, 'page_view',  1001, '{"page": "/home"}',     'New York',  TIMESTAMP '2026-02-28 10:00:00 UTC'),
    (2, 'click',      1002, '{"button": "signup"}',   'London',    TIMESTAMP '2026-02-28 10:05:00 UTC'),
    (3, 'purchase',   1001, '{"item": "pro_plan"}',   'New York',  TIMESTAMP '2026-02-28 11:30:00 UTC'),
    (4, 'page_view',  1003, '{"page": "/pricing"}',   'Tokyo',     TIMESTAMP '2026-02-28 12:00:00 UTC');

-- 4. Query the data
SELECT event_type, COUNT(*) AS cnt
FROM iceberg.demo.events
GROUP BY event_type
ORDER BY cnt DESC;

-- ============================================================
-- TIME TRAVEL — Query historical snapshots (like Snowflake)
-- ============================================================

-- View all snapshots of a table
SELECT * FROM iceberg.demo."events$snapshots";

-- Query data as of a specific snapshot ID
SELECT * FROM iceberg.demo.events
FOR VERSION AS OF <snapshot_id>;

-- Query data as of a specific timestamp
SELECT * FROM iceberg.demo.events
FOR TIMESTAMP AS OF TIMESTAMP '2026-02-28 10:30:00 UTC';

-- ============================================================
-- SCHEMA EVOLUTION (like Snowflake ALTER TABLE)
-- ============================================================

-- Add a new column
ALTER TABLE iceberg.demo.events ADD COLUMN device VARCHAR;

-- Rename a column
ALTER TABLE iceberg.demo.events RENAME COLUMN payload TO event_data;

-- ============================================================
-- PARTITION EVOLUTION (unique to Iceberg — Snowflake can't do this!)
-- ============================================================

-- Change partitioning without rewriting data
ALTER TABLE iceberg.demo.events
SET PROPERTIES partitioning = ARRAY['month(created_at)', 'city'];

-- ============================================================
-- TABLE MAINTENANCE
-- ============================================================

-- Expire old snapshots (data retention)
ALTER TABLE iceberg.demo.events EXECUTE expire_snapshots(retention_threshold => '7d');

-- Compact small files (optimize read performance)
ALTER TABLE iceberg.demo.events EXECUTE optimize WHERE city = 'New York';
