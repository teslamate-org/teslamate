defmodule TeslaMate.Log.State do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__.State
  alias TeslaMate.Log.{Car}

  schema "states" do
    field :state, State

    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    belongs_to(:car, Car)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:state, :start_date, :end_date])
    |> validate_required([:car_id, :state, :start_date])
    |> foreign_key_constraint(:car_id)
  end
end
