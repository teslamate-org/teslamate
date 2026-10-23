-- The aggregates TeslaMate.Log.close_drive/2 (elixir/lib/teslamate/log.ex)
-- computes over the positions of drive $1: its Ecto queries drive_data,
-- non_streamed_drive_data and elevation_data, joined the same way.
-- Both joins are inner: without a position that has a range and an
-- odometer, non_streamed_drive_data is empty and so is the result, which
-- makes close_drive delete the drive.
SELECT
  d0.count,
  d0.start_position_id,
  d0.end_position_id,
  d0.outside_temp_avg,
  d0.inside_temp_avg,
  d0.speed_max,
  d0.power_max,
  d0.power_min,
  d0.start_date,
  d0.end_date,
  d0.start_km,
  d0.end_km,
  d0.distance,
  d0.duration_min,
  d1.start_ideal_range_km,
  d1.end_ideal_range_km,
  d1.start_rated_range_km,
  d1.end_rated_range_km,
  e.elevation_gains AS ascent,
  e.elevation_losses AS descent
FROM (
  SELECT
    count(*) OVER w AS count,
    first_value(p.id) OVER w AS start_position_id,
    last_value(p.id) OVER w AS end_position_id,
    avg(p.outside_temp) OVER w AS outside_temp_avg,
    avg(p.inside_temp) OVER w AS inside_temp_avg,
    max(p.speed) OVER w AS speed_max,
    max(p.power) OVER w AS power_max,
    min(p.power) OVER w AS power_min,
    first_value(p.date) OVER w AS start_date,
    last_value(p.date) OVER w AS end_date,
    first_value(p.odometer) OVER w AS start_km,
    last_value(p.odometer) OVER w AS end_km,
    last_value(p.odometer) OVER w - first_value(p.odometer) OVER w AS distance,
    round(extract(epoch FROM (last_value(p.date) OVER w - first_value(p.date) OVER w)) / 60)::integer AS duration_min
  FROM positions p
  WHERE p.drive_id = $1
  WINDOW w AS (ORDER BY p.date RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  LIMIT 1
) AS d0
INNER JOIN (
  SELECT
    first_value(p.ideal_battery_range_km) OVER w AS start_ideal_range_km,
    last_value(p.ideal_battery_range_km) OVER w AS end_ideal_range_km,
    first_value(p.rated_battery_range_km) OVER w AS start_rated_range_km,
    last_value(p.rated_battery_range_km) OVER w AS end_rated_range_km
  FROM positions p
  WHERE p.drive_id = $1 AND p.ideal_battery_range_km IS NOT NULL AND p.odometer IS NOT NULL
  WINDOW w AS (ORDER BY p.date RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  LIMIT 1
) AS d1 ON true
INNER JOIN (
  -- Sums of gains and of losses above the smallint maximum become 0.
  SELECT
    COALESCE(NULLIF(LEAST(SUM(CASE WHEN p1.elevation_diff > 0 THEN p1.elevation_diff ELSE 0 END), 32768), 32768), 0) AS elevation_gains,
    COALESCE(NULLIF(LEAST(SUM(CASE WHEN p1.elevation_diff < 0 THEN ABS(p1.elevation_diff) ELSE 0 END), 32768), 32768), 0) AS elevation_losses
  FROM (
    SELECT p.elevation - lag(p.elevation) OVER (ORDER BY p.date ASC) AS elevation_diff
    FROM positions p
    WHERE p.drive_id = $1 AND p.elevation IS NOT NULL
  ) AS p1
) AS e ON true
