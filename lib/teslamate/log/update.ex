defmodule TeslaMate.Log.Update do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.Car

  schema "updates" do
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :version, :string

    belongs_to :car, Car
  end

  @doc false
  def changeset(update, attrs) do
    update
    |> cast(attrs, [:start_date, :end_date, :version])
    |> validate_required([:car_id, :start_date])
    |> foreign_key_constraint(:car_id)
    |> check_constraint(:end_date,
      name: :positive_duration,
      message: "end date must be after start date"
    )
  end
end
