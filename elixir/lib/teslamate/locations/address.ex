defmodule TeslaMate.Locations.Address do
  use Ecto.Schema
  import Ecto.Changeset

  schema "addresses" do
    field :city, :string
    field :county, :string
    field :country, :string
    field :display_name, :string
    field :house_number, :string
    field :latitude, :decimal, read_after_writes: true
    field :longitude, :decimal, read_after_writes: true
    field :name, :string
    field :neighbourhood, :string
    field :osm_id, :integer
    field :osm_type, :string
    field :postcode, :string
    field :raw, :map
    field :road, :string
    field :state, :string
    field :state_district, :string

    timestamps()
  end

  @doc false
  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :display_name,
      :osm_id,
      :osm_type,
      :latitude,
      :longitude,
      :name,
      :house_number,
      :road,
      :neighbourhood,
      :city,
      :county,
      :postcode,
      :state,
      :state_district,
      :country,
      :raw
    ])
    |> validate_required([
      :display_name,
      :osm_id,
      :osm_type,
      :latitude,
      :longitude,
      :raw
    ])
    |> unique_constraint(:osm_id, name: :addresses_osm_id_osm_type_index)
  end
end
