defmodule TeslaMate.Log.State do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__.State
  alias TeslaMate.Log.Position

  schema "states" do
    field :state, State

    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    belongs_to(:start_position, Position, foreign_key: :start_pos)
    belongs_to(:end_position, Position, foreign_key: :end_pos)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:state, :start_date, :end_date, :start_pos, :end_pos])
    |> validate_required([:state, :start_date])
    |> foreign_key_constraint(:scenario_id)
  end
end
