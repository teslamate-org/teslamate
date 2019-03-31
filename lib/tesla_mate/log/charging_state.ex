defmodule TeslaMate.Log.ChargingState do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.Charge

  schema "charging_states" do
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime
    field :unplug_date, :utc_datetime
    field :charge_energy_added, :float

    belongs_to(:position, Position, foreign_key: :position_id)
    belongs_to(:charge_start, Charge, foreign_key: :charge_start_id)
    belongs_to(:charge_end, Charge, foreign_key: :charge_end_id)
  end

  @doc false
  def changeset(charging_state, attrs) do
    charging_state
    |> cast(attrs, [
      :start_date,
      :end_date,
      :unplug_date,
      :charge_energy_added,
      :position_id,
      :charge_start_id,
      :charge_end_id
    ])
    |> validate_required([:start_date])
    |> foreign_key_constraint(:position_id)
    |> foreign_key_constraint(:charge_start_id)
    |> foreign_key_constraint(:charge_end_id)
  end
end
