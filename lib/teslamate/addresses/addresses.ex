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

  def get_address!(id), do: Repo.get!(Address, id)

  def create_address(attrs \\ %{}) do
    %Address{}
    |> Address.changeset(attrs)
    |> Repo.insert()
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

  def get_address_by_place_id(place_id) do
    case Address |> Repo.get_by(place_id: place_id) do
      %Address{} = address -> {:ok, address}
      nil -> {:error, :not_found}
    end
  end
end
