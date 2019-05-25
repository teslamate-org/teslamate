defmodule TeslaMate.Log.ChargingProcess do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Charge, Car, Position}
  alias TeslaMate.Addresses.Address

  schema "charging_processes" do
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime
    field :charge_energy_added, :float
    field :start_range_km, :float
    field :end_range_km, :float
    field :start_battery_level, :integer
    field :end_battery_level, :integer
    field :calculated_max_range, :integer
    field :duration_min, :integer
    field :outside_temp_avg, :float

    belongs_to(:car, Car)
    belongs_to(:position, Position)
    belongs_to(:address, Address)

    has_many :charges, Charge
  end

  @doc false
  def changeset(charging_state, attrs) do
    charging_state
    |> cast(attrs, [
      :start_date,
      :end_date,
      :charge_energy_added,
      :start_range_km,
      :end_range_km,
      :start_battery_level,
      :end_battery_level,
      :calculated_max_range,
      :duration_min,
      :outside_temp_avg
    ])
    |> validate_required([:car_id, :start_date])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:position_id)
    |> foreign_key_constraint(:address_id)
    |> cast_assoc(:position, with: &Position.changeset/2, required: true)
  end
end
