-- The Repo.update of TeslaMate.Log.close_drive/2. Ecto writes the
-- aggregates as they are, NULLs included, and a geofence only when one was
-- found, so a missing one keeps the column's value. The address columns are
-- not written: the port runs without address lookup.
-- duration_min, ascent and descent come as integer and bigint and are
-- stored as smallint by Postgres, which fails on overflow as Postgrex does.
UPDATE drives SET
  start_date = $2,
  end_date = $3,
  start_position_id = $4,
  end_position_id = $5,
  outside_temp_avg = $6,
  inside_temp_avg = $7,
  speed_max = $8,
  power_max = $9,
  power_min = $10,
  start_ideal_range_km = $11,
  end_ideal_range_km = $12,
  start_rated_range_km = $13,
  end_rated_range_km = $14,
  start_km = $15,
  end_km = $16,
  distance = $17,
  duration_min = $18::integer,
  ascent = $19::bigint,
  descent = $20::bigint,
  start_geofence_id = COALESCE($21, start_geofence_id),
  end_geofence_id = COALESCE($22, end_geofence_id)
WHERE id = $1
RETURNING
  id,
  car_id,
  start_date,
  end_date,
  start_position_id,
  end_position_id,
  start_address_id,
  end_address_id,
  start_geofence_id,
  end_geofence_id,
  outside_temp_avg,
  inside_temp_avg,
  speed_max,
  power_max,
  power_min,
  start_ideal_range_km,
  end_ideal_range_km,
  start_rated_range_km,
  end_rated_range_km,
  start_km,
  end_km,
  distance,
  duration_min,
  ascent,
  descent
