defmodule TeslaMate.Log.Charge do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.ChargingProcess

  schema "charges" do
    field :battery_level, :integer
    field :charge_energy_added, :float
    field :charger_actual_current, :integer
    field :charger_phases, :integer, default: 1
    field :charger_power, :float
    field :charger_voltage, :integer
    field :battery_heater_on, :boolean
    field :date, :utc_datetime
    field :ideal_battery_range_km, :float
    field :outside_temp, :float

    belongs_to :charging_process, ChargingProcess
  end

  @doc false
  def changeset(charge, attrs) do
    charge
    |> cast(attrs, [
      :date,
      :battery_level,
      :charge_energy_added,
      :charger_power,
      :ideal_battery_range_km,
      :charger_voltage,
      :charger_phases,
      :charger_actual_current,
      :battery_heater_on,
      :outside_temp
    ])
    |> validate_required([
      :date,
      :charging_process_id,
      :battery_level,
      :charge_energy_added,
      :charger_power,
      :ideal_battery_range_km
    ])
    |> foreign_key_constraint(:charging_process_id)
  end
end
