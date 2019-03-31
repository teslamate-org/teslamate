defmodule TeslaMate.Log.Charge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "charges" do
    field :battery_level, :float
    field :charge_energy_added, :float
    field :charger_actual_current, :integer
    field :charger_phases, :integer, default: 1
    field :charger_power, :float
    field :charger_voltage, :integer
    field :date, :utc_datetime
    field :ideal_battery_range, :float
    field :outside_temp, :float
  end

  @doc false
  def changeset(charge, attrs) do
    charge
    |> cast(attrs, [
      :battery_level,
      :charge_energy_added,
      :charger_power,
      :date,
      :ideal_battery_range,
      :charger_voltage,
      :charger_phases,
      :charger_actual_current,
      :outside_temp
    ])
    |> validate_required([
      :battery_level,
      :charge_energy_added,
      :charger_power,
      :date,
      :ideal_battery_range
    ])
  end
end
