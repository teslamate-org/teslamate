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
    %Address{}
    |> Address.changeset(attrs)
    |> Repo.insert()
  end

  def update_address(%Address{} = address, attrs) do
    address
    |> Address.changeset(attrs)
    |> Repo.update()
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

  defp apply_geofence(%GeoFence{id: id} = geofence) do
    alias TeslaMate.Log.{Drive, Position, ChargingProcess}

    {_n, nil} =
      from(d in Drive,
        join: p in Position,
        on: [id: d.start_position_id],
        where: within_geofence?(p, geofence)
      )
      |> Repo.update_all(set: [start_geofence_id: id])

    {_n, nil} =
      from(d in Drive,
        join: p in Position,
        on: [id: d.end_position_id],
        where: within_geofence?(p, geofence)
      )
      |> Repo.update_all(set: [end_geofence_id: id])

    {_n, nil} =
      from(d in ChargingProcess,
        join: p in Position,
        on: [id: d.position_id],
        where: within_geofence?(p, geofence)
      )
      |> Repo.update_all(set: [geofence_id: id])

    :ok
  end

  defp remove_geofence(%GeoFence{id: id}) do
    alias TeslaMate.Log.{Drive, ChargingProcess}

    {_n, nil} =
      Drive
      |> where(start_geofence_id: ^id)
      |> Repo.update_all(set: [start_geofence_id: nil])

    {_n, nil} =
      Drive
      |> where(end_geofence_id: ^id)
      |> Repo.update_all(set: [end_geofence_id: nil])

    {_n, nil} =
      ChargingProcess
      |> where(geofence_id: ^id)
      |> Repo.update_all(set: [geofence_id: nil])

    :ok
  end

  ## GeoFence

  def list_geofences do
    GeoFence
    |> order_by([g], fragment("? COLLATE \"C\" DESC", g.name))
    |> Repo.all()
  end

  def get_geofence!(id) do
    Repo.get!(GeoFence, id)
  end

  def find_geofence(%{latitude: _, longitude: _} = point) do
    GeoFence
    |> select([:id])
    |> where([geofence], within_geofence?(point, geofence, :left))
    |> order_by(:id)
    |> limit(1)
    |> Repo.one()
  end

  def create_geofence(attrs) do
    Repo.transaction(fn ->
      with {:ok, geofence} <- %GeoFence{} |> GeoFence.changeset(attrs) |> Repo.insert(),
           :ok <- apply_geofence(geofence) do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_geofence(%GeoFence{} = geofence, attrs) do
    Repo.transaction(fn ->
      with {:ok, geofence} <- geofence |> GeoFence.changeset(attrs) |> Repo.update(),
           :ok <- remove_geofence(geofence),
           :ok <- apply_geofence(geofence) do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_geofence(%GeoFence{} = geofence) do
    Repo.delete(geofence)
  end

  def change_geofence(%GeoFence{} = geofence, attrs \\ %{}) do
    GeoFence.changeset(geofence, attrs)
  end
end
