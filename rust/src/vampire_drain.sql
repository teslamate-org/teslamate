-- Port of the "Vampire Drain" panel SQL in grafana/dashboards/vampire-drain.json.
-- Kept as close to it as possible; tests/vampire_drain.rs compares the two.
-- Deviations, all value-preserving:
-- * The Grafana variables are bind parameters:
--   $1 $car_id, $2 and $3 the range of $__timeFilter(start_date),
--   $4 $duration (hours), $5 ${preferred_range}, $6 $length_unit.
-- * ${preferred_range} chose the range columns by splicing "ideal" or "rated"
--   into their names. A CASE on $5 chooses them instead, so the SQL is static
--   and checked at compile time. $5 and $6 are cast to their PostgreSQL
--   enums, so any other value is an error rather than a silent NULL.
-- * The unit is no longer part of the column names range_diff_$length_unit
--   and range_lost_per_hour_${length_unit}.
-- * The final ORDER BY makes the row order part of the result; the dashboard
--   relies on the order of the v CTE surviving the joins.
WITH merge AS (
  SELECT
    c.start_date AS start_date,
    c.end_date AS end_date,
    c.start_ideal_range_km AS start_ideal_range_km,
    c.end_ideal_range_km AS end_ideal_range_km,
    c.start_rated_range_km AS start_rated_range_km,
    c.end_rated_range_km AS end_rated_range_km,
    start_battery_level,
    end_battery_level,
    p.usable_battery_level AS start_usable_battery_level,
    NULL AS end_usable_battery_level,
    p.odometer AS start_km,
    p.odometer AS end_km
  FROM charging_processes c
  JOIN positions p ON c.position_id = p.id
  WHERE c.car_id = $1 AND start_date BETWEEN $2 AND $3
  UNION
  SELECT
    d.start_date AS start_date,
    d.end_date AS end_date,
    d.start_ideal_range_km AS start_ideal_range_km,
    d.end_ideal_range_km AS end_ideal_range_km,
    d.start_rated_range_km AS start_rated_range_km,
    d.end_rated_range_km AS end_rated_range_km,
    start_position.battery_level AS start_battery_level,
    end_position.battery_level AS end_battery_level,
    start_position.usable_battery_level AS start_usable_battery_level,
    end_position.usable_battery_level AS end_usable_battery_level,
    d.start_km AS start_km,
    d.end_km AS end_km
  FROM drives d
  JOIN positions start_position ON d.start_position_id = start_position.id
  JOIN positions end_position ON d.end_position_id = end_position.id
  WHERE d.car_id = $1 AND start_date BETWEEN $2 AND $3
),
v AS (
  SELECT
    lag(t.end_date) OVER w AS start_date,
    t.start_date AS end_date,
    lag(CASE $5::preferred_range
      WHEN 'ideal' THEN t.end_ideal_range_km
      WHEN 'rated' THEN t.end_rated_range_km
    END) OVER w AS start_range,
    CASE $5::preferred_range
      WHEN 'ideal' THEN t.start_ideal_range_km
      WHEN 'rated' THEN t.start_rated_range_km
    END AS end_range,
    lag(t.end_km) OVER w AS start_km,
    t.start_km AS end_km,
    EXTRACT(EPOCH FROM (t.start_date - lag(t.end_date) OVER w)) AS duration,
    lag(t.end_battery_level) OVER w AS start_battery_level,
    lag(t.end_usable_battery_level) OVER w AS start_usable_battery_level,
    start_battery_level AS end_battery_level,
    start_usable_battery_level AS end_usable_battery_level,
    start_battery_level > COALESCE(start_usable_battery_level, start_battery_level) AS has_reduced_range
  FROM merge t
  WINDOW w AS (ORDER BY t.start_date ASC)
  ORDER BY start_date DESC
)
SELECT
  floor(extract(epoch FROM v.start_date)) * 1000 AS start_date_ts,
  ceil(extract(epoch FROM v.end_date)) * 1000 AS end_date_ts,
  v.start_date,
  v.end_date,
  v.duration,
  coalesce(s_standby.sleep, 0) / v.duration AS standby,
  -greatest(v.start_battery_level - v.end_battery_level, 0) AS soc_diff,
  CASE WHEN has_reduced_range THEN 1 ELSE 0 END AS has_reduced_range,
  convert_km(CASE WHEN has_reduced_range THEN NULL ELSE (v.start_range - v.end_range)::numeric END, $6::unit_of_length::text) AS range_diff,
  CASE WHEN has_reduced_range THEN NULL ELSE (v.start_range - v.end_range) * c.efficiency END AS consumption,
  CASE WHEN has_reduced_range THEN NULL ELSE ((v.start_range - v.end_range) * c.efficiency) / (v.duration / 3600) * 1000 END AS avg_power,
  convert_km(CASE WHEN has_reduced_range THEN NULL ELSE ((v.start_range - v.end_range) / (v.duration / 3600))::numeric END, $6::unit_of_length::text) AS range_lost_per_hour
FROM v,
  LATERAL (
    SELECT EXTRACT(EPOCH FROM sum(
      LEAST(s.end_date, v.end_date)
      - GREATEST(s.start_date, v.start_date)
    )) AS sleep
    FROM states s
    WHERE
      state IN ('asleep', 'offline') AND
      s.start_date < v.end_date AND
      (s.end_date IS NULL OR s.end_date > v.start_date) AND
      s.car_id = $1
  ) s_standby
JOIN cars c ON c.id = $1
WHERE
  v.duration > ($4 * 60 * 60)
  AND v.start_range - v.end_range >= 0
  AND v.end_km - v.start_km < 1
ORDER BY v.start_date DESC
