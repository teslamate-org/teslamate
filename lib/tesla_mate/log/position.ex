defmodule TeslaMate.Log.Position do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Car, Trip}

  schema "positions" do
    field :date, :utc_datetime
    field :latitude, :float
    field :longitude, :float

    field :speed, :integer
    field :power, :integer
    field :odometer, :float
    field :ideal_battery_range_km, :float
    field :battery_level, :float
    field :outside_temp, :float
    field :altitude, :float

    belongs_to(:car, Car)
    belongs_to(:trip, Trip)
  end

  @doc false
  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :date,
      :latitude,
      :longitude,
      :speed,
      :power,
      :odometer,
      :ideal_battery_range_km,
      :battery_level,
      :outside_temp,
      :altitude
    ])
    |> validate_required([:car_id, :date, :latitude, :longitude])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:trip_id)
  end
end
