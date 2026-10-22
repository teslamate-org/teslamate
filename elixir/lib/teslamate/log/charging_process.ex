defmodule TeslaMate.Log.ChargingProcess do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Locations.{Address, GeoFence}
  alias TeslaMate.Log.{Charge, Car, Position}

  schema "charging_processes" do
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :charge_energy_added, :decimal, read_after_writes: true
    field :charge_energy_used, :decimal, read_after_writes: true
    field :start_ideal_range_km, :decimal, read_after_writes: true
    field :end_ideal_range_km, :decimal, read_after_writes: true
    field :start_rated_range_km, :decimal, read_after_writes: true
    field :end_rated_range_km, :decimal, read_after_writes: true
    field :start_battery_level, :integer
    field :end_battery_level, :integer
    field :duration_min, :integer
    field :outside_temp_avg, :decimal, read_after_writes: true
    field :cost, :decimal, read_after_writes: true

    belongs_to(:car, Car)
    belongs_to(:position, Position)
    belongs_to(:address, Address)
    belongs_to(:geofence, GeoFence)

    has_many :charges, Charge
  end

  @doc false
  def changeset(charging_state, attrs) do
    charging_state
    |> cast(attrs, [
      :geofence_id,
      :address_id,
      :start_date,
      :end_date,
      :charge_energy_added,
      :charge_energy_used,
      :start_ideal_range_km,
      :end_ideal_range_km,
      :start_rated_range_km,
      :end_rated_range_km,
      :start_battery_level,
      :end_battery_level,
      :duration_min,
      :outside_temp_avg,
      :cost
    ])
    |> validate_required([:car_id, :start_date])
    |> validate_number(:charge_energy_added, greater_than_or_equal_to: 0)
    |> validate_number(:charge_energy_used, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:position_id)
    |> foreign_key_constraint(:address_id)
    |> foreign_key_constraint(:geofence_id)
    |> cast_assoc(:position, with: &Position.changeset/2)
  end
end
