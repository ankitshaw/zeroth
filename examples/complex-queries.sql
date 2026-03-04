-- ============================================================
-- Zeroth — Complex Analytical Queries
-- ============================================================
-- Run these after producing 100k events and NiFi ingestion.
-- Execute via: docker exec trino trino < examples/complex-queries.sql
-- Or paste into Superset SQL Lab (localhost:8088)
-- ============================================================


-- ============================================================
-- 1. REAL-TIME DASHBOARD — Events per minute (last 24 hours)
-- ============================================================
SELECT
    date_trunc('minute', created_at) AS minute,
    count(*)                         AS events,
    count(DISTINCT user_id)          AS unique_users
FROM iceberg.demo.events
WHERE created_at > current_timestamp - INTERVAL '24' HOUR
GROUP BY 1
ORDER BY 1 DESC
LIMIT 60;


-- ============================================================
-- 2. FUNNEL ANALYSIS — Conversion funnel by city
-- ============================================================
SELECT
    city,
    count(DISTINCT CASE WHEN event_type = 'page_view'    THEN user_id END) AS viewers,
    count(DISTINCT CASE WHEN event_type = 'add_to_cart'  THEN user_id END) AS added_to_cart,
    count(DISTINCT CASE WHEN event_type = 'checkout'     THEN user_id END) AS checked_out,
    count(DISTINCT CASE WHEN event_type = 'purchase'     THEN user_id END) AS purchased,
    ROUND(
        100.0 * count(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END)
        / NULLIF(count(DISTINCT CASE WHEN event_type = 'page_view' THEN user_id END), 0)
    , 2) AS conversion_rate_pct
FROM iceberg.demo.events
GROUP BY city
ORDER BY viewers DESC;


-- ============================================================
-- 3. USER COHORT ANALYSIS — Retention by signup week
-- ============================================================
WITH user_first_event AS (
    SELECT
        user_id,
        date_trunc('week', min(created_at)) AS cohort_week
    FROM iceberg.demo.events
    GROUP BY user_id
),
user_activity AS (
    SELECT
        e.user_id,
        u.cohort_week,
        date_diff('week', u.cohort_week, date_trunc('week', e.created_at)) AS weeks_since_signup
    FROM iceberg.demo.events e
    JOIN user_first_event u ON e.user_id = u.user_id
)
SELECT
    cohort_week,
    count(DISTINCT CASE WHEN weeks_since_signup = 0 THEN user_id END) AS week_0,
    count(DISTINCT CASE WHEN weeks_since_signup = 1 THEN user_id END) AS week_1,
    count(DISTINCT CASE WHEN weeks_since_signup = 2 THEN user_id END) AS week_2,
    count(DISTINCT CASE WHEN weeks_since_signup = 3 THEN user_id END) AS week_3,
    ROUND(
        100.0 * count(DISTINCT CASE WHEN weeks_since_signup = 1 THEN user_id END)
        / NULLIF(count(DISTINCT CASE WHEN weeks_since_signup = 0 THEN user_id END), 0)
    , 1) AS week1_retention_pct
FROM user_activity
GROUP BY cohort_week
ORDER BY cohort_week;


-- ============================================================
-- 4. SESSIONIZATION — Detect user sessions (30-min gap)
-- ============================================================
WITH ordered_events AS (
    SELECT
        user_id,
        event_type,
        city,
        created_at,
        lag(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_event_at
    FROM iceberg.demo.events
),
sessions AS (
    SELECT
        *,
        CASE
            WHEN prev_event_at IS NULL
              OR created_at > prev_event_at + INTERVAL '30' MINUTE
            THEN 1 ELSE 0
        END AS new_session
    FROM ordered_events
),
session_ids AS (
    SELECT
        *,
        sum(new_session) OVER (PARTITION BY user_id ORDER BY created_at) AS session_id
    FROM sessions
)
SELECT
    user_id,
    session_id,
    count(*)                                                  AS events_in_session,
    min(created_at)                                           AS session_start,
    max(created_at)                                           AS session_end,
    date_diff('second', min(created_at), max(created_at))     AS duration_seconds,
    array_agg(DISTINCT event_type)                            AS event_types,
    array_agg(DISTINCT city)                                  AS cities
FROM session_ids
GROUP BY user_id, session_id
HAVING count(*) >= 3
ORDER BY duration_seconds DESC
LIMIT 20;


-- ============================================================
-- 5. TOP POWER USERS — By event volume and diversity
-- ============================================================
SELECT
    user_id,
    count(*)                               AS total_events,
    count(DISTINCT event_type)             AS unique_event_types,
    count(DISTINCT city)                   AS unique_cities,
    count(DISTINCT date_trunc('day', created_at)) AS active_days,
    min(created_at)                        AS first_seen,
    max(created_at)                        AS last_seen,
    date_diff('day', min(created_at), max(created_at)) AS lifespan_days
FROM iceberg.demo.events
GROUP BY user_id
ORDER BY total_events DESC
LIMIT 25;


-- ============================================================
-- 6. HOURLY HEATMAP — Events by day-of-week × hour-of-day
-- ============================================================
SELECT
    CASE day_of_week(created_at)
        WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue' WHEN 3 THEN 'Wed'
        WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri' WHEN 6 THEN 'Sat'
        WHEN 7 THEN 'Sun'
    END AS day_name,
    day_of_week(created_at)   AS day_num,
    hour(created_at)          AS hour_of_day,
    count(*)                  AS event_count
FROM iceberg.demo.events
GROUP BY day_of_week(created_at), hour(created_at)
ORDER BY day_num, hour_of_day;


-- ============================================================
-- 7. EVENT VELOCITY — Detect traffic spikes (Z-score)
-- ============================================================
WITH hourly AS (
    SELECT
        date_trunc('hour', created_at) AS hour,
        count(*)                       AS events
    FROM iceberg.demo.events
    GROUP BY 1
),
stats AS (
    SELECT
        avg(events)    AS mean_events,
        stddev(events) AS stddev_events
    FROM hourly
)
SELECT
    h.hour,
    h.events,
    ROUND((h.events - s.mean_events) / NULLIF(s.stddev_events, 0), 2) AS z_score,
    CASE
        WHEN (h.events - s.mean_events) / NULLIF(s.stddev_events, 0) > 2  THEN '🔴 SPIKE'
        WHEN (h.events - s.mean_events) / NULLIF(s.stddev_events, 0) < -2 THEN '🔵 DROP'
        ELSE '🟢 NORMAL'
    END AS status
FROM hourly h
CROSS JOIN stats s
ORDER BY z_score DESC
LIMIT 20;


-- ============================================================
-- 8. CITY-TO-CITY FLOW — Users who appear in multiple cities
-- ============================================================
WITH city_pairs AS (
    SELECT
        user_id,
        city AS from_city,
        lead(city) OVER (PARTITION BY user_id ORDER BY created_at) AS to_city
    FROM iceberg.demo.events
)
SELECT
    from_city,
    to_city,
    count(DISTINCT user_id) AS unique_travelers,
    count(*)                AS transitions
FROM city_pairs
WHERE to_city IS NOT NULL
  AND from_city != to_city
GROUP BY from_city, to_city
ORDER BY transitions DESC
LIMIT 20;


-- ============================================================
-- 9. TIME TRAVEL — Compare current vs. 1 hour ago
-- ============================================================
-- (Requires at least 2 snapshots)
SELECT
    'current'       AS version,
    count(*)        AS total_rows,
    count(DISTINCT user_id)  AS unique_users,
    max(created_at) AS latest_event
FROM iceberg.demo.events

UNION ALL

SELECT
    'previous_snapshot' AS version,
    count(*)            AS total_rows,
    count(DISTINCT user_id)  AS unique_users,
    max(created_at)     AS latest_event
FROM iceberg.demo.events
FOR VERSION AS OF (
    SELECT max(snapshot_id)
    FROM iceberg.demo."events$snapshots"
    WHERE committed_at < current_timestamp - INTERVAL '1' HOUR
);


-- ============================================================
-- 10. METADATA — Iceberg table health check
-- ============================================================

-- Snapshot history
SELECT
    snapshot_id,
    parent_id,
    committed_at,
    operation
FROM iceberg.demo."events$snapshots"
ORDER BY committed_at DESC
LIMIT 10;

-- File sizes and counts
SELECT
    count(*)                                     AS total_files,
    sum(file_size_in_bytes) / 1024 / 1024        AS total_size_mb,
    avg(file_size_in_bytes) / 1024               AS avg_file_size_kb,
    sum(record_count)                            AS total_records
FROM iceberg.demo."events$files";
