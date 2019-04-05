defmodule TeslaMate.Log.Trip do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Position, Car}

  schema "trips" do
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    field :outside_temp_avg, :float

    field :speed_max, :integer

    field :power_max, :float
    field :power_min, :float
    field :power_avg, :float

    field :start_range_km, :float
    field :end_range_km, :float

    field :start_km, :float
    field :end_km, :float
    field :distance, :float
    field :duration_min, :integer

    # TODO Address ref
    field :start_address, :string
    field :end_address, :string

    field :consumption_kWh, :float
    field :consumption_kWh_100km, :float

    belongs_to(:car, Car)

    has_many :positions, Position
  end

  @doc false
  def changeset(trip, attrs) do
    trip
    |> cast(attrs, [
      :start_date,
      :end_date,
      :outside_temp_avg,
      :speed_max,
      :power_max,
      :power_min,
      :power_avg,
      :start_range_km,
      :end_range_km,
      :start_km,
      :end_km,
      :distance,
      :duration_min,
      :start_address,
      :end_address,
      :consumption_kWh,
      :consumption_kWh_100km
    ])
    |> validate_required([:car_id, :start_date])
    |> foreign_key_constraint(:car_id)
  end
end
