defmodule TeslaMate.Locations.GeoFence do
  use Ecto.Schema

  import Ecto.Changeset

  schema "geofences" do
    field :name, :string
    field :latitude, :float
    field :longitude, :float
    field :radius, :float

    field :cost_per_kwh, :decimal
    field :session_fee, :decimal

    timestamps()
  end

  @doc false
  def changeset(geofence, attrs) do
    geofence
    |> cast(attrs, [
      :name,
      :radius,
      :latitude,
      :longitude,
      :cost_per_kwh,
      :session_fee
    ])
    |> validate_required([:name, :latitude, :longitude, :radius])
    |> validate_number(:radius, greater_than: 0, less_than: 5000)
    |> validate_number(:cost_per_kwh, greater_than_or_equal_to: 0)
    |> validate_number(:session_fee, greater_than_or_equal_to: 0)
  end
end
