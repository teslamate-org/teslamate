defmodule TeslaMate.Log.Position do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Car, Drive}

  schema "positions" do
    field :date, :utc_datetime
    field :latitude, :float
    field :longitude, :float
    field :elevation, :float

    field :speed, :integer
    field :power, :float
    field :odometer, :float
    field :ideal_battery_range_km, :float
    field :est_battery_range_km, :float
    field :rated_battery_range_km, :float
    field :battery_level, :integer
    field :battery_heater, :boolean
    field :battery_heater_on, :boolean
    field :battery_heater_no_power, :boolean
    field :outside_temp, :float
    field :inside_temp, :float
    field :fan_status, :integer
    field :driver_temp_setting, :float
    field :passenger_temp_setting, :float
    field :is_climate_on, :boolean
    field :is_rear_defroster_on, :boolean
    field :is_front_defroster_on, :boolean

    belongs_to(:car, Car)
    belongs_to(:drive, Drive)
  end

  @doc false
  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :car_id,
      :date,
      :latitude,
      :longitude,
      :elevation,
      :speed,
      :power,
      :odometer,
      :ideal_battery_range_km,
      :est_battery_range_km,
      :rated_battery_range_km,
      :battery_level,
      :battery_heater_no_power,
      :battery_heater_on,
      :battery_heater,
      :inside_temp,
      :outside_temp,
      :fan_status,
      :driver_temp_setting,
      :passenger_temp_setting,
      :is_climate_on,
      :is_rear_defroster_on,
      :is_front_defroster_on
    ])
    |> validate_required([:car_id, :date, :latitude, :longitude])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:drive_id)
  end
end
