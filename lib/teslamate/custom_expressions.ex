defmodule TeslaMate.CustomExpressions do
  import Ecto.Query, warn: false

  defmacro c_if(condition, do: do_clause, else: else_clause) do
    quote do
      fragment(
        "CASE WHEN ? THEN ? ELSE ? END",
        unquote(condition),
        unquote(do_clause),
        unquote(else_clause)
      )
    end
  end

  defmacro duration_min(a, b) do
    quote do
      fragment(
        "(EXTRACT(EPOCH FROM (?::timestamp - ?::timestamp)) / 60)::integer",
        unquote(a),
        unquote(b)
      )
    end
  end

  defmacro nullif(a, b) do
    quote do
      fragment("NULLIF(?, ?)", unquote(a), unquote(b))
    end
  end

  defmacro round(v, s) do
    quote do
      fragment("ROUND((?)::numeric, ?)::float8", unquote(v), unquote(s))
    end
  end

  defmacro within_geofence?(position, geofence, direction \\ :right)

  defmacro within_geofence?(position, geofence, :right) do
    quote do
      fragment(
        """
        earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?) AND
        earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < ?
        """,
        ^unquote(geofence).latitude,
        ^unquote(geofence).longitude,
        ^unquote(geofence).radius,
        unquote(position).latitude,
        unquote(position).longitude,
        ^unquote(geofence).latitude,
        ^unquote(geofence).longitude,
        unquote(position).latitude,
        unquote(position).longitude,
        ^unquote(geofence).radius
      )
    end
  end

  defmacro within_geofence?(position, geofence, :left) do
    quote do
      fragment(
        """
        earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?) AND
        earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < ?
        """,
        unquote(geofence).latitude,
        unquote(geofence).longitude,
        unquote(geofence).radius,
        ^unquote(position).latitude,
        ^unquote(position).longitude,
        unquote(geofence).latitude,
        unquote(geofence).longitude,
        ^unquote(position).latitude,
        ^unquote(position).longitude,
        unquote(geofence).radius
      )
    end
  end

  defmacro distance(geofence, position) do
    quote do
      fragment(
        "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?))",
        unquote(geofence).latitude,
        unquote(geofence).longitude,
        ^unquote(position).latitude,
        ^unquote(position).longitude
      )
    end
  end
end
