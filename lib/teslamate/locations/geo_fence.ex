defmodule TeslaMate.Locations.GeoFence do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Locations.Address

  schema "geofences" do
    field :name, :string
    field :latitude, :float
    field :longitude, :float
    field :radius, :float

    belongs_to :address, Address

    timestamps()
  end

  @doc false
  def changeset(geofence, attrs) do
    geofence
    |> cast(attrs, [:name, :radius, :latitude, :longitude])
    |> validate_required([:name, :latitude, :longitude, :radius])
    |> validate_number(:radius, greater_than: 0, less_than: 1000)
    |> foreign_key_constraint(:address_id)
    |> unique_constraint(:address_id, name: :geofences_address_id_index)
  end
end
