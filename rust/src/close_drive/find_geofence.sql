-- TeslaMate.Locations.find_geofence/1 for position $1: the nearest geofence
-- whose radius contains the position, via the earthdistance extension
-- (within_geofence?/3 and distance/2 in
-- elixir/lib/teslamate/custom_expressions.ex). Elixir binds the position's
-- coordinates; reading them from the row gives the same values.
SELECT g.id
FROM geofences g
JOIN positions p ON p.id = $1
WHERE
  earth_box(ll_to_earth(g.latitude::numeric, g.longitude::numeric), g.radius) @> ll_to_earth(p.latitude::numeric, p.longitude::numeric)
  AND earth_distance(ll_to_earth(g.latitude::numeric, g.longitude::numeric), ll_to_earth(p.latitude::numeric, p.longitude::numeric)) < g.radius
ORDER BY earth_distance(ll_to_earth(g.latitude::numeric, g.longitude::numeric), ll_to_earth(p.latitude::numeric, p.longitude::numeric)) ASC
LIMIT 1
