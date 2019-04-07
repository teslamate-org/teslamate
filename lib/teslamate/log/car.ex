defmodule TeslaMate.Log.Car do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{ChargingProcess, Position, Trip}

  schema "cars" do
    field :efficiency, :float
    field :eid, :integer
    field :model, :string
    field :vid, :integer

    has_many :charging_processes, ChargingProcess
    has_many :positions, Position
    has_many :trips, Trip

    timestamps()
  end

  @doc false
  def changeset(car, attrs) do
    car
    |> cast(attrs, [:model, :efficiency])
    |> validate_required([:eid, :vid, :model, :efficiency])
    |> unique_constraint(:eid)
    |> unique_constraint(:vid)
  end
end
