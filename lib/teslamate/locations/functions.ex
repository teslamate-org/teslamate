defmodule TeslaMate.Locations.Functions do
  import Ecto.Query, warn: false

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
end
