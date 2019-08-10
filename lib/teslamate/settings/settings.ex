defmodule TeslaMate.Settings.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Settings.Units

  schema "settings" do
    field :unit_of_length, Units.Length
    field :unit_of_temperature, Units.Temperature
    field :suspend_min, :integer
    field :suspend_after_idle_min, :integer

    timestamps()
  end

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, [:unit_of_length, :unit_of_temperature, :suspend_min, :suspend_after_idle_min])
    |> validate_required([
      :unit_of_length,
      :unit_of_temperature,
      :suspend_min,
      :suspend_after_idle_min
    ])
  end
end
