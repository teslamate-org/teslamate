defmodule TeslaMate.Settings.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Settings.Units

  schema "settings" do
    field :unit_of_length, Units.Length
    field :unit_of_temperature, Units.Temperature

    timestamps()
  end

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, [:unit_of_length, :unit_of_temperature])
    |> validate_required([:unit_of_length, :unit_of_temperature])
  end
end
