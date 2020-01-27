defmodule TeslaMate.Locations do
  @moduledoc """
  The Locations context.
  """

  require Logger

  import Ecto.Query, warn: false
  import TeslaMate.CustomExpressions

  alias __MODULE__.{Address, Geocoder, GeoFence, Cache}
  alias TeslaMate.Log.{Drive, Position, ChargingProcess}
  alias TeslaMate.Settings.GlobalSettings
  alias TeslaMate.{Repo, Settings}

  def child_spec(_arg) do
    %{id: __MODULE__, start: {Cachex, :start_link, [Cache, [limit: 100]]}}
  end

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
    with %GlobalSettings{language: lang} <- Settings.get_global_settings!(),
         {:ok, %{osm_id: id, osm_type: type} = attrs} <- @geocoder.reverse_lookup(lat, lng, lang) do
      case Repo.get_by(Address, osm_id: id, osm_type: type) do
        %Address{} = address -> {:ok, address}
        nil -> create_address(attrs)
      end
    end
  end

  def refresh_addresses(lang) do
    Address
    |> Repo.all()
    |> Enum.chunk_every(50)
    |> Enum.with_index()
    |> Enum.each(fn {addresses, i} ->
      if i > 0, do: Process.sleep(1500)

      {:ok, attrs} = @geocoder.details(addresses, lang)

      addresses
      |> merge_addresses(attrs)
      |> Enum.map(fn
        {%Address{osm_id: id, osm_type: type} = address, attrs} ->
          attrs =
            with nil <- attrs do
              {:ok, %{osm_id: ^id, osm_type: ^type} = attrs} =
                Geocoder.reverse_lookup(address.latitude, address.longitude, lang)

              Process.sleep(1500)

              attrs
            end
            |> Map.take([
              :city,
              :country,
              :county,
              :display_name,
              :neighbourhood,
              :state,
              :state_district
            ])

          {:ok, _} = update_address(address, attrs)
      end)
    end)
  rescue
    e in MatchError -> {:error, with({:error, reason} <- e.term, do: reason)}
  end

  defp merge_addresses(addresses, attrs) do
    addresses =
      Enum.reduce(addresses, %{}, fn %Address{osm_id: id, osm_type: type} = address, acc ->
        Map.put(acc, {type, id}, {address, nil})
      end)

    attrs
    |> Enum.reduce(addresses, fn %{osm_id: id, osm_type: type} = attrs, acc ->
      Map.update!(acc, {type, id}, fn {address, nil} -> {address, attrs} end)
    end)
    |> Map.values()
  end

  defp apply_geofence(%GeoFence{id: id} = geofence) do
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
    GeoFence
    |> Repo.get!(id)
    |> Repo.preload([:sleep_mode_blacklist, :sleep_mode_whitelist])
  end

  def find_geofence(%{latitude: _, longitude: _} = point) do
    GeoFence
    |> select([:id])
    |> where([geofence], within_geofence?(point, geofence, :left))
    |> order_by(:id)
    |> limit(1)
    |> Repo.one()
  end

  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Log.Car

  def may_fall_asleep_at?(
        %Car{id: id, settings: %CarSettings{sleep_mode_enabled: enabled}},
        %{latitude: lat, longitude: lng} = position
      ) do
    key = {id, {lat, lng}, enabled}

    result =
      Cachex.fetch(Cache, key, fn ->
        assoc = if enabled, do: :sleep_mode_blacklist, else: :sleep_mode_whitelist

        query =
          GeoFence
          |> select([:id])
          |> join(:left, [geofence], c in assoc(geofence, ^assoc))
          |> where([geofence, c], c.id == ^id and within_geofence?(position, geofence, :left))
          |> limit(1)

        may_fall_asleep? =
          if enabled do
            Repo.one(query) == nil
          else
            Repo.one(query) != nil
          end

        {:commit, may_fall_asleep?}
      end)

    with {:commit, value} <- result do
      Logger.debug("Inserted #{value} into #{Cache} for #{inspect(key)}")
      {:ok, value}
    end
  end

  def clear_cache do
    with {:ok, n} <- Cachex.clear(Cache) do
      Logger.debug("Removed #{n} entrie(s) from #{Cache}")
      :ok
    end
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
           :ok <- apply_geofence(geofence),
           :ok <- clear_cache() do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_geofence(%GeoFence{} = geofence) do
    Repo.transaction(fn ->
      with :ok <- remove_geofence(geofence),
           {:ok, geofence} <- Repo.delete(geofence),
           :ok <- clear_cache() do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change_geofence(%GeoFence{} = geofence, attrs \\ %{}) do
    GeoFence.changeset(geofence, attrs)
  end
end
