defmodule TeslaMate.Log.Position do
  use Ecto.Schema
  import Ecto.Changeset

  schema "positions" do
    field :date, :utc_datetime
    field :latitude, :float
    field :longitude, :float
    field :speed, :integer
    field :power, :integer
    field :odometer, :float
    field :ideal_battery_range, :float
    field :battery_level, :float
    field :outside_temp, :float
    field :altitude, :float
  end

  @doc false
  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :date,
      :latitude,
      :longitude,
      :speed,
      :power,
      :odometer,
      :ideal_battery_range,
      :battery_level,
      :outside_temp,
      :altitude
    ])
    |> validate_required([:date, :latitude, :longitude])
  end
end
