defmodule TeslaMate.Settings.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :use_imperial_units, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, [:use_imperial_units])
    |> validate_required([:use_imperial_units])
  end
end
