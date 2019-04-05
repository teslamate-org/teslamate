defmodule TeslaMate.Log.ChargingProcess do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Charge, Car, Position}

  schema "charging_processes" do
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    # TODO add fields
    field :charge_energy_added, :float
    # complete_date

    belongs_to(:car, Car)
    belongs_to(:position, Position)

    has_many :charges, Charge
  end

  # TODO position required?
  @doc false
  def changeset(charging_state, attrs) do
    charging_state
    |> cast(attrs, [:position_id, :start_date, :end_date, :charge_energy_added])
    |> validate_required([:car_id, :start_date])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:position_id)
    |> cast_assoc(:position, with: &Position.changeset/2)
  end
end
