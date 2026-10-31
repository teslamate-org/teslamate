defmodule TeslaMate.Locations do
  @moduledoc """
  The Locations context.
  """

  require Logger

  import Ecto.Query, warn: false
  import TeslaMate.CustomExpressions

  alias __MODULE__.{Address, Geocoder, GeoFence}
  alias TeslaMate.Log.{Drive, ChargingProcess}
  alias TeslaMate.Settings.GlobalSettings
  alias TeslaMate.{Mutex, Repo, Settings}

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
               _ -> Geocoder
             end)

  def find_address(%{latitude: lat, longitude: lng}) do
    %GlobalSettings{language: lang} = Settings.get_global_settings!()

    case nominatim(fn -> @geocoder.reverse_lookup(lat, lng, lang) end) do
      {:ok, %{osm_id: id, osm_type: type} = attrs} ->
        case Repo.get_by(Address, osm_id: id, osm_type: type) do
          %Address{} = address -> {:ok, address}
          nil -> create_address(attrs)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Nominatim's usage policy allows one request per second, for the whole app:
  # every request runs under this mutex, which spaces them for all processes.
  @nominatim __MODULE__.Nominatim
  @nominatim_interval 1500

  @doc """
  The options of the mutex that every request to Nominatim runs under. Start
  it before anything that looks up addresses.
  """
  def nominatim_mutex do
    [
      name: @nominatim,
      interval: @nominatim_interval,
      clock: Function.capture(@geocoder, :now, 0),
      pause: Function.capture(@geocoder, :pause, 1)
    ]
  end

  defp nominatim(fun), do: Mutex.run(@nominatim, fun)

  @localized_fields [
    :city,
    :country,
    :county,
    :display_name,
    :neighbourhood,
    :state,
    :state_district
  ]

  @doc """
  Fetches all addresses from Nominatim in the language `lang`, without writing
  anything. Pass the result to `update_addresses/1`.

  This takes a while with many addresses: requests are paced to Nominatim's
  usage policy. So call it outside of a transaction, which would hold a
  database connection that long.

  An address that Nominatim now reports as a different place is skipped.
  """
  def fetch_localized_addresses(lang) do
    chunks =
      Address
      |> Repo.all()
      |> Enum.chunk_every(50)

    with {:ok, localized} <- collect(chunks, &fetch_localized_chunk(&1, lang)) do
      {:ok, Enum.concat(localized)}
    end
  end

  defp fetch_localized_chunk(addresses, lang) do
    with {:ok, attrs} <- nominatim(fn -> @geocoder.details(addresses, lang) end) do
      addresses
      |> merge_addresses(attrs)
      |> collect(&localize(&1, lang))
    end
  end

  defp localize({%Address{osm_type: "unknown"}, _attrs}, _lang) do
    :skip
  end

  defp localize({%Address{} = address, attrs}, _lang) when is_map(attrs) do
    {:ok, {address, Map.take(attrs, @localized_fields)}}
  end

  # The lookup did not return the address
  defp localize({%Address{osm_id: id, osm_type: type} = address, nil}, lang) do
    case nominatim(fn -> @geocoder.reverse_lookup(address.latitude, address.longitude, lang) end) do
      {:ok, %{osm_id: ^id, osm_type: ^type} = attrs} ->
        {:ok, {address, Map.take(attrs, @localized_fields)}}

      {:ok, attrs} ->
        Logger.warning("""
        Address does not match! Skipping …

          osm_id: #{id} -> #{attrs[:osm_id]}
          osm_type: #{type} -> #{attrs[:osm_type]}

        """)

        :skip

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Writes the addresses fetched by `fetch_localized_addresses/1`.

  Writes only the fields that differ from the addresses as fetched, so no
  other refresh of the addresses may run in between. Stops at the first
  failure, so run it inside a transaction to write all of them or none.
  """
  def update_addresses(localized) do
    with {:ok, _addresses} <-
           collect(localized, fn {%Address{} = address, attrs} ->
             update_address(address, attrs)
           end) do
      :ok
    end
  end

  # Applies `fun` to each element in order and collects the results until the
  # first error. A `:skip` adds nothing.
  defp collect(enumerable, fun) do
    enumerable
    |> Enum.reduce_while({:ok, []}, fn element, {:ok, acc} ->
      case fun.(element) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        :skip -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
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
            earth_distance(ll_to_earth(g.latitude, g.longitude), ll_to_earth(p.latitude, p.longitude)) < g.radius AND
            g.id != $4
          ORDER BY
            earth_distance(ll_to_earth(g.latitude, g.longitude), ll_to_earth(p.latitude, p.longitude)) ASC
          LIMIT 1
        )
        FROM positions p
        WHERE
          m.#{position_field} = p.id AND
          earth_box(ll_to_earth($1::numeric, $2::numeric), $3) @> ll_to_earth(p.latitude, p.longitude) AND
          earth_distance(ll_to_earth($1::numeric, $2::numeric), ll_to_earth(p.latitude, p.longitude)) < $3
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
    |> order_by([g], fragment("? COLLATE \"C\" ASC", g.name))
    |> Repo.all()
  end

  def get_geofence!(id) do
    Repo.get!(GeoFence, id)
  end

  def find_geofence(%{latitude: _, longitude: _} = point) do
    GeoFence
    |> select([:id, :name])
    |> where([geofence], within_geofence?(point, geofence, :left))
    |> order_by([geofence], asc: distance(geofence, point))
    |> limit(1)
    |> Repo.one()
  end

  # Subscribers learn that a geofence was created, changed or deleted: the
  # geofence of a position depends on the definitions too.
  @geofences_topic "#{inspect(__MODULE__)}/geofences"

  def subscribe_to_geofences do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, @geofences_topic)
  end

  defp notify_geofences({:ok, _geofence} = result) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, @geofences_topic, :geofences_changed)
    result
  end

  defp notify_geofences(result), do: result

  def create_geofence(attrs) do
    Repo.transaction(fn ->
      with {:ok, geofence} <- %GeoFence{} |> GeoFence.changeset(attrs) |> Repo.insert(),
           :ok <- apply_geofence(geofence) do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> notify_geofences()
  end

  def update_geofence(%GeoFence{id: id} = geofence, attrs) do
    changeset = GeoFence.changeset(geofence, attrs)

    if location_changed?(changeset) do
      Repo.transaction(fn ->
        with :ok <- apply_geofence(geofence, except: id),
             {:ok, geofence} <- Repo.update(changeset),
             :ok <- apply_geofence(geofence) do
          geofence
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      Repo.update(changeset)
    end
    |> notify_geofences()
  end

  # Drives and charging processes are assigned to geofences by location and radius only
  defp location_changed?(changeset) do
    Enum.any?([:latitude, :longitude, :radius], &Ecto.Changeset.changed?(changeset, &1))
  end

  def delete_geofence(%GeoFence{id: id} = geofence) do
    Repo.transaction(fn ->
      with :ok <- apply_geofence(geofence, except: id),
           {:ok, geofence} <- Repo.delete(geofence) do
        geofence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> notify_geofences()
  end

  def change_geofence(%GeoFence{} = geofence, attrs \\ %{}) do
    GeoFence.changeset(geofence, attrs)
  end

  alias TeslaMate.Log.ChargingProcess

  def count_charging_processes_without_costs(%{latitude: _, longitude: _, radius: _} = geofence) do
    Repo.one(
      from c in ChargingProcess,
        select: count(),
        join: p in assoc(c, :position),
        where: is_nil(c.cost) and within_geofence?(p, geofence, :right)
    )
  end

  def calculate_charge_costs(%GeoFence{id: id}) do
    query = """
    UPDATE charging_processes cp
    SET cost = (
      SELECT
        CASE WHEN g.session_fee IS NULL AND g.cost_per_unit IS NULL THEN
               NULL
             WHEN g.billing_type = 'per_kwh' THEN
               COALESCE(g.session_fee, 0) +
               COALESCE(g.cost_per_unit * GREATEST(c.charge_energy_used, c.charge_energy_added), 0)
             WHEN g.billing_type = 'per_minute' THEN
               COALESCE(g.session_fee, 0) +
               COALESCE(g.cost_per_unit * c.duration_min, 0)
        END
      FROM charging_processes c
      JOIN geofences g ON g.id = c.geofence_id
      WHERE cp.id = c.id
    )
    WHERE cp.geofence_id = $1 AND cp.cost IS NULL;
    """

    with {:ok, %Postgrex.Result{num_rows: _}} <- Repo.query(query, [id]) do
      :ok
    end
  end
end
