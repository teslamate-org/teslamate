defmodule TeslaMate.Log.Car do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.{ChargingProcess, Position, Drive}
  alias TeslaMate.Settings.CarSettings

  @type t :: %__MODULE__{}

  schema "cars" do
    field :name, :string
    field :efficiency, :float
    field :model, :string
    field :trim_badging, :string
    field :marketing_name, :string
    field :exterior_color, :string
    field :wheel_type, :string
    field :spoiler_type, :string

    field :eid, :integer
    field :vid, :integer
    field :vin, :string
    field :display_priority, :integer

    belongs_to :settings, CarSettings

    has_many :charging_processes, ChargingProcess
    has_many :positions, Position
    has_many :drives, Drive

    timestamps()
  end

  @doc false
  def changeset(car, attrs) do
    car
    |> cast(attrs, [
      :eid,
      :vid,
      :vin,
      :name,
      :model,
      :efficiency,
      :trim_badging,
      :marketing_name,
      :exterior_color,
      :wheel_type,
      :spoiler_type,
      :display_priority
    ])
    |> update_change(:name, &trim_name/1)
    |> validate_length(:name, max: 64)
    |> validate_required([:eid, :vid, :vin])
    |> unique_constraint(:settings_id)
    |> unique_constraint(:eid)
    |> unique_constraint(:vin)
    |> unique_constraint(:vid)
  end

  defp trim_name(nil), do: nil

  defp trim_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
