defmodule TeslaMate.Log.Position do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Car, Trip}

  schema "positions" do
    field :date, :utc_datetime
    field :latitude, :float
    field :longitude, :float

    field :speed, :integer
    field :power, :float
    field :odometer, :float
    field :ideal_battery_range_km, :float
    field :battery_level, :integer
    field :outside_temp, :float
    field :altitude, :float
    field :fan_status, :integer
    field :driver_temp_setting, :float
    field :passenger_temp_setting, :float
    field :is_climate_on, :boolean
    field :is_rear_defroster_on, :boolean
    field :is_front_defroster_on, :boolean

    belongs_to(:car, Car)
    belongs_to(:trip, Trip)
  end

  @doc false
  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :car_id,
      :date,
      :latitude,
      :longitude,
      :speed,
      :power,
      :odometer,
      :ideal_battery_range_km,
      :battery_level,
      :outside_temp,
      :altitude,
      :fan_status,
      :driver_temp_setting,
      :passenger_temp_setting,
      :is_climate_on,
      :is_rear_defroster_on,
      :is_front_defroster_on
    ])
    |> validate_required([:car_id, :date, :latitude, :longitude])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:trip_id)
  end
end
