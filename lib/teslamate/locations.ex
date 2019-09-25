defmodule TeslaMate.Locations do
  @moduledoc """
  The Locations context.
  """

  import Ecto.Query, warn: false
  import __MODULE__.Functions

  alias TeslaMate.Repo
  alias __MODULE__.{Address, Geocoder, GeoFence}

  ## Address

  def create_address(attrs \\ %{}) do
    with {:ok, address} <- validate_address(attrs) do
      geofence_id =
        with %GeoFence{id: id} <- get_geofence(address) do
          id
        end

      %Address{}
      |> Address.changeset(Map.put(attrs, :geofence_id, geofence_id))
      |> Repo.insert()
    end
  end

  def update_address(%Address{} = address, attrs) do
    address
    |> Address.changeset(attrs)
    |> Repo.update()
  end

  defp validate_address(attrs) do
    %Address{}
    |> change_address(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  def change_address(%Address{} = address, attrs \\ %{}) do
    Address.changeset(address, attrs)
  end

  @geocoder (case Mix.env() do
               :test -> GeocoderMock
               _____ -> Geocoder
             end)

  def find_address(%{latitude: lat, longitude: lng}) do
    with {:ok, %{place_id: place_id} = attrs} <- @geocoder.reverse_lookup(lat, lng) do
      case Repo.get_by(Address, place_id: place_id) do
        %Address{} = address -> {:ok, address}
        nil -> create_address(attrs)
      end
    end
  end

  defp apply_geofence_to_addresses(%GeoFence{} = geofence) do
    {_n, nil} =
      Address
      |> where([a], within_geofence?(a, geofence))
      |> Repo.update_all(set: [geofence_id: geofence.id])

    :ok
  end

  defp remove_geofence_from_addresses(%GeoFence{id: id}) do
    {_n, nil} =
      Address
      |> where(geofence_id: ^id)
      |> Repo.update_all(set: [geofence_id: nil])

    :ok
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

  defp get_geofence(%Address{} = address) do
    from(
      geofence in GeoFence,
      select: [:id],
      where: within_geofence?(address, geofence, :left),
      order_by: :id,
      limit: 1
    )
    |> Repo.one()
  end

  def create_geofence(attrs) do
    with {:ok, %GeoFence{latitude: lat, longitude: lng}} <- validate_geofence(attrs) do
      Repo.transaction(fn ->
        with {:ok, _address} <- find_address(%{latitude: lat, longitude: lng}),
             {:ok, geofence} <- %GeoFence{} |> GeoFence.changeset(attrs) |> Repo.insert(),
             :ok <- apply_geofence_to_addresses(geofence) do
          geofence
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def update_geofence(%GeoFence{} = geofence, attrs) do
    with {:ok, %GeoFence{latitude: lat, longitude: lng}} <- validate_geofence(attrs) do
      Repo.transaction(fn ->
        with {:ok, _address} <- find_address(%{latitude: lat, longitude: lng}),
             {:ok, geofence} <- geofence |> GeoFence.changeset(attrs) |> Repo.update(),
             :ok <- remove_geofence_from_addresses(geofence),
             :ok <- apply_geofence_to_addresses(geofence) do
          geofence
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
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
