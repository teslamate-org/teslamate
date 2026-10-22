-- Port of the "Drive" panel SQL in grafana/dashboards/drives.json.
-- Kept as close to it as possible; tests/drives.rs compares the two.
-- Deviations, all value-preserving for the dashboard's settings:
-- * The Grafana variables are bind parameters:
--   $1 $car_id, $2 and $3 the range of $__timeFilter, $4 $length_unit,
--   $5 $temp_unit, $6 ${preferred_range}, $7 $min_dist, $8 $min_speed,
--   $9 $geofence, $10 $location, $11 $efficiency.
-- * ${preferred_range} chose the range columns by splicing "ideal" or "rated"
--   into their names. A CASE on $6 chooses them instead, so the SQL is static.
-- * $geofence: NULL stands for "All" (the dashboard's custom all value -1,
--   tested with '${geofence:pipe}' = '-1'), otherwise the selected ids.
-- * $location: NULL for no filter. The dashboard's empty text box matches
--   every row instead, as '%%' matches any address and the addresses are
--   never NULL (CONCAT_WS returns '' at worst). Like the dashboard, % and _
--   in the text are LIKE wildcards; a quote is no longer able to break out.
-- * The units are no longer part of the column names, and the columns
--   "% Start", "% End" and "consumption_kWh" get plain names.
-- * The final ORDER BY sorts by the column named in $12 ($13 'asc' or
--   'desc', NULLs last either way), then by drive id, newest first. Without
--   $12 that is the dashboard's order. Grafana sorts the table in the
--   browser instead; the port adds the sort. ORDER BY cannot use output
--   column names inside expressions, hence the outer SELECT.
SELECT *
FROM (
  WITH data AS (
    SELECT
      floor(extract(epoch FROM start_date)) * 1000 AS start_date_ts,
      ceil(extract(epoch FROM end_date)) * 1000 AS end_date_ts,
      car.id AS car_id,
      CASE
        WHEN start_geofence.id IS NULL THEN CONCAT('new?lat=', start_position.latitude, '&lng=', start_position.longitude)
        WHEN start_geofence.id IS NOT NULL THEN CONCAT(start_geofence.id, '/edit')
      END AS start_path,
      CASE
        WHEN end_geofence.id IS NULL THEN CONCAT('new?lat=', end_position.latitude, '&lng=', end_position.longitude)
        WHEN end_geofence.id IS NOT NULL THEN CONCAT(end_geofence.id, '/edit')
      END AS end_path,
      TO_CHAR((duration_min * INTERVAL '1 minute'), 'HH24:MI') AS duration_str,
      drives.id AS drive_id,
      start_date,
      COALESCE(start_geofence.name, CONCAT_WS(', ', COALESCE(start_address.name, nullif(CONCAT_WS(' ', start_address.road, start_address.house_number), '')), COALESCE(start_address.city, start_address.neighbourhood))) AS start_address,
      COALESCE(end_geofence.name, CONCAT_WS(', ', COALESCE(end_address.name, nullif(CONCAT_WS(' ', end_address.road, end_address.house_number), '')), COALESCE(end_address.city, end_address.neighbourhood))) AS end_address,
      duration_min,
      distance,
      start_position.battery_level AS start_battery_level,
      end_position.battery_level AS end_battery_level,
      CASE $6::preferred_range
        WHEN 'ideal' THEN start_ideal_range_km - end_ideal_range_km
        WHEN 'rated' THEN start_rated_range_km - end_rated_range_km
      END AS range_diff,
      car.efficiency AS car_efficiency,
      outside_temp_avg,
      distance / coalesce(NULLIF(duration_min, 0) * 60, extract(epoch FROM end_date - start_date)) * 3600 AS avg_speed,
      speed_max,
      power_max,
      ascent,
      descent
    FROM drives
    LEFT JOIN addresses start_address ON start_address_id = start_address.id
    LEFT JOIN addresses end_address ON end_address_id = end_address.id
    LEFT JOIN positions start_position ON start_position_id = start_position.id
    LEFT JOIN positions end_position ON end_position_id = end_position.id
    LEFT JOIN geofences start_geofence ON start_geofence_id = start_geofence.id
    LEFT JOIN geofences end_geofence ON end_geofence_id = end_geofence.id
    LEFT JOIN cars car ON car.id = drives.car_id
    WHERE start_date BETWEEN $2 AND $3 AND drives.car_id = $1
      AND convert_km(distance::numeric, $4::unit_of_length::text) >= $7::numeric
      AND convert_km(distance::numeric, $4::unit_of_length::text) / coalesce(NULLIF(duration_min, 0) * 60, extract(epoch FROM end_date - start_date)) * 3600 >= $8::numeric
      AND ($9::integer[] IS NULL OR start_geofence.id = ANY($9) OR end_geofence.id = ANY($9))
  ),

  reduced_range_info AS (
    SELECT
      drive_id,
      CASE
        WHEN sum(CASE WHEN battery_level - usable_battery_level > 0 THEN 1 ELSE 0 END)::numeric / count(*) > 0.25 THEN true
        ELSE false
      END AS reduced_range
    FROM positions p
    WHERE date BETWEEN $2 AND $3 AND car_id = $1 AND p.ideal_battery_range_km IS NOT NULL
    GROUP BY p.drive_id
  )

  SELECT
    start_date_ts,
    end_date_ts,
    car_id,
    start_path,
    end_path,
    duration_str,
    data.drive_id,
    start_date,
    start_address,
    end_address,
    duration_min,
    convert_km(distance::numeric, $4::unit_of_length::text) AS distance,
    start_battery_level,
    end_battery_level,
    convert_celsius(outside_temp_avg, $5::unit_of_temperature::text) AS outside_temp,
    convert_km(avg_speed::numeric, $4::unit_of_length::text) AS speed_avg,
    convert_km(speed_max::numeric, $4::unit_of_length::text) AS speed_max,
    power_max,
    reduced_range AS has_reduced_range,
    CASE
      WHEN range_diff > 0 AND 'by distance' = $11::text THEN distance / range_diff
      WHEN 'slope-adjusted' = $11::text THEN
        distance * car_efficiency -- Energy at 100% efficiency
        / nullif((
             (range_diff) * car_efficiency -- Actual Energy
             + 2100 * 0.85 * 9.81 * descent / 3600 / 1000 -- Potential energy recovered from descent
             - 2100 * 9.81 * ascent / 3600 / 1000 -- Potential energy for ascent
        ), 0)
      ELSE NULL
    END AS efficiency,
    range_diff * car_efficiency AS consumption_kwh,
    range_diff * car_efficiency / convert_km(distance::numeric, $4::unit_of_length::text) * 1000 AS consumption_wh_per_distance
  FROM data
    LEFT JOIN reduced_range_info ON data.drive_id = reduced_range_info.drive_id
  WHERE
    $10::text IS NULL
    OR start_address ILIKE ('%' || $10 || '%')
    OR end_address ILIKE ('%' || $10 || '%')
) AS drives_list
ORDER BY
  CASE WHEN $12::text = 'start_date' AND $13::text = 'asc' THEN start_date END ASC NULLS LAST,
  CASE WHEN $12::text = 'start_date' AND $13::text = 'desc' THEN start_date END DESC NULLS LAST,
  CASE WHEN $12::text = 'start_address' AND $13::text = 'asc' THEN start_address END ASC NULLS LAST,
  CASE WHEN $12::text = 'start_address' AND $13::text = 'desc' THEN start_address END DESC NULLS LAST,
  CASE WHEN $12::text = 'end_address' AND $13::text = 'asc' THEN end_address END ASC NULLS LAST,
  CASE WHEN $12::text = 'end_address' AND $13::text = 'desc' THEN end_address END DESC NULLS LAST,
  CASE WHEN $12::text = 'duration_min' AND $13::text = 'asc' THEN duration_min END ASC NULLS LAST,
  CASE WHEN $12::text = 'duration_min' AND $13::text = 'desc' THEN duration_min END DESC NULLS LAST,
  CASE WHEN $12::text = 'distance' AND $13::text = 'asc' THEN distance END ASC NULLS LAST,
  CASE WHEN $12::text = 'distance' AND $13::text = 'desc' THEN distance END DESC NULLS LAST,
  CASE WHEN $12::text = 'start_battery_level' AND $13::text = 'asc' THEN start_battery_level END ASC NULLS LAST,
  CASE WHEN $12::text = 'start_battery_level' AND $13::text = 'desc' THEN start_battery_level END DESC NULLS LAST,
  CASE WHEN $12::text = 'end_battery_level' AND $13::text = 'asc' THEN end_battery_level END ASC NULLS LAST,
  CASE WHEN $12::text = 'end_battery_level' AND $13::text = 'desc' THEN end_battery_level END DESC NULLS LAST,
  CASE WHEN $12::text = 'outside_temp' AND $13::text = 'asc' THEN outside_temp END ASC NULLS LAST,
  CASE WHEN $12::text = 'outside_temp' AND $13::text = 'desc' THEN outside_temp END DESC NULLS LAST,
  CASE WHEN $12::text = 'speed_avg' AND $13::text = 'asc' THEN speed_avg END ASC NULLS LAST,
  CASE WHEN $12::text = 'speed_avg' AND $13::text = 'desc' THEN speed_avg END DESC NULLS LAST,
  CASE WHEN $12::text = 'speed_max' AND $13::text = 'asc' THEN speed_max END ASC NULLS LAST,
  CASE WHEN $12::text = 'speed_max' AND $13::text = 'desc' THEN speed_max END DESC NULLS LAST,
  CASE WHEN $12::text = 'power_max' AND $13::text = 'asc' THEN power_max END ASC NULLS LAST,
  CASE WHEN $12::text = 'power_max' AND $13::text = 'desc' THEN power_max END DESC NULLS LAST,
  CASE WHEN $12::text = 'has_reduced_range' AND $13::text = 'asc' THEN has_reduced_range END ASC NULLS LAST,
  CASE WHEN $12::text = 'has_reduced_range' AND $13::text = 'desc' THEN has_reduced_range END DESC NULLS LAST,
  CASE WHEN $12::text = 'efficiency' AND $13::text = 'asc' THEN efficiency END ASC NULLS LAST,
  CASE WHEN $12::text = 'efficiency' AND $13::text = 'desc' THEN efficiency END DESC NULLS LAST,
  CASE WHEN $12::text = 'consumption_kwh' AND $13::text = 'asc' THEN consumption_kwh END ASC NULLS LAST,
  CASE WHEN $12::text = 'consumption_kwh' AND $13::text = 'desc' THEN consumption_kwh END DESC NULLS LAST,
  CASE WHEN $12::text = 'consumption_wh_per_distance' AND $13::text = 'asc' THEN consumption_wh_per_distance END ASC NULLS LAST,
  CASE WHEN $12::text = 'consumption_wh_per_distance' AND $13::text = 'desc' THEN consumption_wh_per_distance END DESC NULLS LAST,
  drive_id DESC
