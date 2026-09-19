defmodule TeslaMate.Log.Position do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Car, Drive}

  schema "positions" do
    field :date, :utc_datetime_usec
    field :latitude, :decimal, read_after_writes: true
    field :longitude, :decimal, read_after_writes: true
    field :elevation, :integer

    field :speed, :integer
    field :power, :integer
    field :odometer, :float
    field :ideal_battery_range_km, :decimal, read_after_writes: true
    field :est_battery_range_km, :decimal, read_after_writes: true
    field :rated_battery_range_km, :decimal, read_after_writes: true
    field :battery_level, :integer
    field :usable_battery_level, :integer
    field :battery_heater, :boolean
    field :battery_heater_on, :boolean
    field :battery_heater_no_power, :boolean
    field :outside_temp, :decimal, read_after_writes: true
    field :inside_temp, :decimal, read_after_writes: true
    field :fan_status, :integer
    field :driver_temp_setting, :decimal, read_after_writes: true
    field :passenger_temp_setting, :decimal, read_after_writes: true
    field :is_climate_on, :boolean
    field :is_rear_defroster_on, :boolean
    field :is_front_defroster_on, :boolean
    field :tpms_pressure_fl, :decimal
    field :tpms_pressure_fr, :decimal
    field :tpms_pressure_rl, :decimal
    field :tpms_pressure_rr, :decimal

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
      :usable_battery_level,
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
      :is_front_defroster_on,
      :tpms_pressure_fl,
      :tpms_pressure_fr,
      :tpms_pressure_rl,
      :tpms_pressure_rr
    ])
    |> validate_required([:car_id, :date, :latitude, :longitude])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:drive_id)
  end
end
