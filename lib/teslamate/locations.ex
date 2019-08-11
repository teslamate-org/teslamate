defmodule TeslaMate.Locations do
  @moduledoc """
  The Locations context.
  """

  import Ecto.Query, warn: false

  alias TeslaMate.Repo

  alias TeslaMate.Locations.{Address, Geocoder, GeoFence}

  ## Address

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

  def find_address(%{latitude: lat, longitude: lng}) do
    case find_geofenced_address(lat, lng) do
      nil -> reverse_geocode(lat, lng)
      addr -> {:ok, addr}
    end
  end

  defp reverse_geocode(lat, lng) do
    with {:ok, %{place_id: place_id} = attrs} <- @geocoder.reverse_lookup(lat, lng) do
      case Repo.get_by(Address, place_id: place_id) do
        %Address{} = address -> {:ok, address}
        nil -> create_address(attrs)
      end
    end
  end

  defp find_geofenced_address(lat, lng) do
    geofences = list_geofences()

    with %GeoFence{} = geofence <-
           Enum.find(geofences, fn %GeoFence{radius: radius} = geofence ->
             Geocalc.within?(radius, geofence, {lat, lng})
           end),
         %GeoFence{address: address} <- Repo.preload(geofence, :address) do
      address
    end
  end

  ## GeoFence

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
