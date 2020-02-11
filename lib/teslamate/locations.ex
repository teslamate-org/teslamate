defmodule TeslaMate.Locations do
  @moduledoc """
  The Locations context.
  """

  require Logger

  import Ecto.Query, warn: false
  import TeslaMate.CustomExpressions

  alias __MODULE__.{Address, Geocoder, GeoFence, Cache}
  alias TeslaMate.Log.{Drive, ChargingProcess}
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

  defp apply_geofence(%GeoFence{latitude: lat, longitude: lng, radius: r}, opts \\ []) do
    except_id = Keyword.get(opts, :except) || -1
    args = [lat, lng, r, except_id]

    q = fn module, geofence_field, position_field ->
      """
        UPDATE #{module.__schema__(:source)} m
        SET #{geofence_field} = (
          SELECT id
          FROM geofences g
          WHERE
            earth_box(ll_to_earth(g.latitude, g.longitude), g.radius) @> ll_to_earth(p.latitude, p.longitude) AND
            earth_distance(ll_to_earth(g.latitude, g.longitude), ll_to_earth(latitude, p.longitude)) < g.radius AND
            g.id != $4
          ORDER BY
            earth_distance(ll_to_earth(g.latitude, g.longitude), ll_to_earth(latitude, p.longitude)) ASC
          LIMIT 1
        )
        FROM positions p
        WHERE
          m.#{position_field} = p.id AND
          earth_box(ll_to_earth($1, $2), $3) @> ll_to_earth(p.latitude, p.longitude) AND
          earth_distance(ll_to_earth($1, $2), ll_to_earth(latitude, p.longitude)) < $3
      """
    end

    Drive |> q.(:start_geofence_id, :start_position_id) |> Repo.query!(args)
    Drive |> q.(:end_geofence_id, :end_position_id) |> Repo.query!(args)
    ChargingProcess |> q.(:geofence_id, :position_id) |> Repo.query!(args)

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
    |> select([:id, :name])
    |> where([geofence], within_geofence?(point, geofence, :left))
    |> order_by([geofence], asc: distance(geofence, point))
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

  def update_geofence(%GeoFence{id: id} = geofence, attrs) do
    Repo.transaction(fn ->
      with :ok <- apply_geofence(geofence, except: id),
           {:ok, geofence} <- geofence |> GeoFence.changeset(attrs) |> Repo.update(),
           :ok <- apply_geofence(geofence),
           :ok <- clear_cache() do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_geofence(%GeoFence{id: id} = geofence) do
    Repo.transaction(fn ->
      with :ok <- apply_geofence(geofence, except: id),
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
