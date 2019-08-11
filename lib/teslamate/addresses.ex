defmodule TeslaMate.Addresses do
  @moduledoc """
  The Addresses context.
  """

  import Ecto.Query, warn: false

  alias TeslaMate.Repo

  ## Address

  alias TeslaMate.Addresses.{Address, Geocoder}

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

  @geocoder (case Mix.env() do
               :test -> GeocoderMock
               _____ -> Geocoder
             end)

  def find_address(%{latitude: latitude, longitude: longitude}) do
    with {:ok, %{place_id: place_id} = attrs} <- @geocoder.reverse_lookup(latitude, longitude) do
      case Repo.get_by(Address, place_id: place_id) do
        %Address{} = address -> {:ok, address}
        nil -> create_address(attrs)
      end
    end
  end

  ## GeoFence

  alias TeslaMate.Addresses.GeoFence

  def list_geofences do
    GeoFence
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_geofence!(id) do
    Repo.get!(GeoFence, id)
  end

  def create_geofence(attrs) do
    with {:ok, %GeoFence{latitude: lat, longitude: lng}} <- validate_geofence(attrs) do
      Repo.transaction(fn ->
        with {:ok, %Address{id: id}} <- find_address(%{latitude: lat, longitude: lng}),
             {:ok, gf} <- %GeoFence{address_id: id} |> GeoFence.changeset(attrs) |> Repo.insert() do
          gf
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def update_geofence(%GeoFence{} = geofence, attrs) do
    # Updating the coordinats would require to change the address.
    attrs = Map.drop(attrs, [:latitude, :longitude])

    geofence
    |> GeoFence.changeset(attrs)
    |> Repo.update()
  end

  def delete_geofence(%GeoFence{} = geofence) do
    Repo.delete(geofence)
  end

  def change_geofence(%GeoFence{} = geofence, attrs \\ %{}) do
    GeoFence.changeset(geofence, attrs)
  end

  defp validate_geofence(attrs) do
    %GeoFence{}
    |> change_geofence(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end
end
