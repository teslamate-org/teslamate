defmodule TeslaMate.Addresses.Address do
  use Ecto.Schema
  import Ecto.Changeset

  schema "addresses" do
    field :city, :string
    field :county, :string
    field :country, :string
    field :display_name, :string
    field :house_number, :string
    field :latitude, :float
    field :longitude, :float
    field :name, :string
    field :neighbourhood, :string
    field :place_id, :integer
    field :postcode, :string
    field :raw, :map
    field :road, :string
    field :state, :string

    timestamps()
  end

  @doc false
  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :display_name,
      :place_id,
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
      :country,
      :raw
    ])
    |> validate_required([
      :display_name,
      :place_id,
      :latitude,
      :longitude,
      :raw
    ])
    |> unique_constraint(:place_id)
  end
end
