defmodule TeslaMate.Log.State do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.Car

  schema "states" do
    field :state, Ecto.Enum, values: [:online, :offline, :asleep]

    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec

    belongs_to(:car, Car)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:state, :start_date, :end_date])
    |> validate_required([:car_id, :state, :start_date])
    |> foreign_key_constraint(:car_id)
    |> unique_constraint(:end_date,
      name: :states_car_id__end_date_IS_NULL_index,
      message: "the current state must first be completed"
    )
    |> check_constraint(:end_date,
      name: :positive_duration,
      message: "end date must be after start date"
    )
  end
end
