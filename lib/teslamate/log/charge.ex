defmodule TeslaMate.Log.Charge do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.ChargingProcess

  schema "charges" do
    field :date, :utc_datetime_usec
    field :battery_heater, :boolean
    field :battery_heater_on, :boolean
    field :battery_heater_no_power, :boolean
    field :battery_level, :integer
    field :usable_battery_level, :integer
    field :charge_energy_added, :decimal, read_after_writes: true
    field :charger_actual_current, :integer
    field :charger_phases, :integer, default: 1
    field :charger_pilot_current, :integer
    field :charger_power, :integer
    field :charger_voltage, :integer
    field :conn_charge_cable, :string
    field :fast_charger_present, :boolean
    field :fast_charger_brand, :string
    field :fast_charger_type, :string
    field :ideal_battery_range_km, :decimal, read_after_writes: true
    field :rated_battery_range_km, :decimal, read_after_writes: true
    field :not_enough_power_to_heat, :boolean
    field :outside_temp, :decimal, read_after_writes: true

    belongs_to :charging_process, ChargingProcess
  end

  @doc false
  def changeset(charge, attrs) do
    charge
    |> cast(attrs, [
      :date,
      :battery_heater_no_power,
      :battery_heater_on,
      :battery_heater,
      :battery_level,
      :usable_battery_level,
      :charge_energy_added,
      :charger_actual_current,
      :charger_phases,
      :charger_pilot_current,
      :charger_power,
      :charger_voltage,
      :conn_charge_cable,
      :fast_charger_present,
      :fast_charger_brand,
      :fast_charger_type,
      :ideal_battery_range_km,
      :rated_battery_range_km,
      :not_enough_power_to_heat,
      :outside_temp
    ])
    |> validate_required([
      :date,
      :charging_process_id,
      :charge_energy_added,
      :charger_power,
      :ideal_battery_range_km
    ])
    |> validate_number(:charger_phases, greater_than: 0)
    |> foreign_key_constraint(:charging_process_id)
  end
end
