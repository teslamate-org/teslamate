defmodule TeslaMate.Addresses do
  @moduledoc """
  The Addresses context.
  """

  import Ecto.Query, warn: false

  alias TeslaMate.Addresses.{Address, Geocoder}
  alias TeslaMate.Repo

  def list_addresses do
    Repo.all(Address)
  end

  def get_address!(id) do
    Repo.get!(Address, id)
  end

  def create_address(attrs \\ %{}) do
    %Address{}
    |> Address.changeset(attrs)
    |> Repo.insert()
  end

  def create_address_if_not_exists(%{place_id: place_id} = attrs) do
    case Repo.get_by(Address, place_id: place_id) do
      %Address{} = address -> {:ok, address}
      nil -> create_address(attrs)
    end
  end

  def update_address(%Address{} = address, attrs) do
    address
    |> Address.changeset(attrs)
    |> Repo.update()
  end

  def delete_address(%Address{} = address) do
    Repo.delete(address)
  end

  def change_address(%Address{} = address) do
    Address.changeset(address, %{})
  end

  @geocoder (case Mix.env() do
               :test -> GeocoderMock
               _____ -> Geocoder
             end)

  def find_address(%{latitude: latitude, longitude: longitude}) do
    with {:ok, attrs} <- @geocoder.reverse_lookup(latitude, longitude) do
      create_address_if_not_exists(attrs)
    end
  end
end
