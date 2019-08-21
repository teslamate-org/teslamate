defmodule TeslaMate.Log.Drive do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{Position, Car}
  alias TeslaMate.Locations.Address

  schema "drives" do
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime
    field :outside_temp_avg, :float
    field :inside_temp_avg, :float
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
    field :efficiency, :float

    belongs_to :start_address, Address
    belongs_to :end_address, Address
    belongs_to :car, Car

    has_many :positions, Position, on_delete: :delete_all
  end

  @doc false
  def changeset(drive, attrs) do
    drive
    |> cast(attrs, [
      :start_date,
      :end_date,
      :start_address_id,
      :end_address_id,
      :outside_temp_avg,
      :inside_temp_avg,
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
      :efficiency
    ])
    |> validate_required([:car_id, :start_date])
    |> foreign_key_constraint(:car_id)
    |> foreign_key_constraint(:start_address)
    |> foreign_key_constraint(:end_address)
  end
end
