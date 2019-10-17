defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  require Logger

  import TeslaMate.CustomExpressions
  import Ecto.Query, warn: false

  alias TeslaMate.{Repo, Locations, Mapping, Settings}

  ## Car

  alias TeslaMate.Log.Car

  def list_cars do
    Repo.all(Car)
  end

  def get_car!(id) do
    Repo.get!(Car, id)
  end

  def get_car_by([{_key, nil}]), do: nil
  def get_car_by([{_key, _val}] = opts), do: Repo.get_by(Car, opts)

  def create_car(attrs) do
    %Car{}
    |> Car.changeset(attrs)
    |> Repo.insert()
  end

  def create_or_update_car(%Ecto.Changeset{} = changeset) do
    Repo.insert_or_update(changeset)
  end

  def update_car(%Car{} = car, attrs) do
    car
    |> Car.changeset(attrs)
    |> Repo.update()
  end

  def recalculate_efficiencies(%Settings.Settings{} = settings) do
    for car <- list_cars() do
      {:ok, _car} = recalculate_efficiency(car, settings)
    end

    :ok
  end

  ## State

  alias TeslaMate.Log.State

  def start_state(car_id, state) when not is_nil(car_id) and not is_nil(state) do
    now = DateTime.utc_now()

    case get_current_state(car_id) do
      %State{state: ^state} = s ->
        {:ok, s}

      %State{} = s ->
        Repo.transaction(fn ->
          with {:ok, _} <- s |> State.changeset(%{end_date: now}) |> Repo.update(),
               {:ok, new_state} <- create_state(car_id, %{state: state, start_date: now}) do
            new_state
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      nil ->
        create_state(car_id, %{state: state, start_date: now})
    end
  end

  def get_current_state(car_id) do
    State
    |> where([s], ^car_id == s.car_id and is_nil(s.end_date))
    |> Repo.one()
  end

  defp create_state(car_id, attrs) do
    %State{car_id: car_id}
    |> State.changeset(attrs)
    |> Repo.insert()
  end

  ## Position

  alias TeslaMate.Log.Position

  @mapping (case Mix.env() do
              :test -> MappingMock
              _____ -> Mapping
            end)

  def insert_position(car_id, %{latitude: lat, longitude: lng} = attrs) do
    elevation = @mapping.get_elevation({lat, lng})
    attrs = Map.put(attrs, :elevation, elevation)

    %Position{car_id: car_id, drive_id: Map.get(attrs, :drive_id)}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  def get_latest_position do
    Position
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
  end

  def get_latest_position(car_id) do
    Position
    |> where(car_id: ^car_id)
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
  end

  def get_positions_without_elevation(min_id \\ 0, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Position
    |> where([p], p.id > ^min_id and is_nil(p.elevation))
    |> order_by(asc: :id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
    |> case do
      [%Position{id: next} | _] = positions ->
        {Enum.reverse(positions), next}

      [] ->
        {[], nil}
    end
  end

  def update_position(%Position{} = position, attrs) do
    position
    |> Position.changeset(attrs)
    |> Repo.update()
  end

  ## Drive

  alias TeslaMate.Log.Drive

  def start_drive(car_id) do
    with {:ok, %Drive{id: id}} <-
           %Drive{car_id: car_id}
           |> Drive.changeset(%{start_date: DateTime.utc_now()})
           |> Repo.insert() do
      {:ok, id}
    end
  end

  def close_drive(drive_id) do
    drive =
      Drive
      |> preload([:car])
      |> Repo.get!(drive_id)

    query =
      Position
      |> select([p], %{
        id: p.id,
        date: p.date,
        latitude: p.latitude,
        longitude: p.longitude,
        odometer: p.odometer,
        ideal_battery_range_km: p.ideal_battery_range_km,
        rated_battery_range_km: p.rated_battery_range_km,
        power_avg: avg(p.power) |> over(),
        outside_temp_avg: avg(p.outside_temp) |> over(),
        inside_temp_avg: avg(p.inside_temp) |> over(),
        speed_max: max(p.speed) |> over(),
        power_max: max(p.power) |> over(),
        power_min: min(p.power) |> over(),
        first_row: row_number() |> over(order_by: [asc: p.date]),
        last_row: row_number() |> over(order_by: [desc: p.date])
      })
      |> where(drive_id: ^drive_id)
      |> order_by(asc: :date)

    positions =
      subquery(query)
      |> where([p], p.first_row == 1 or p.last_row == 1)
      |> Repo.all()

    case positions do
      [] ->
        drive |> Drive.changeset(%{distance: 0, duration_min: 0}) |> Repo.delete()

      [_] ->
        drive |> Drive.changeset(%{distance: 0, duration_min: 0}) |> Repo.delete()

      [start_pos, end_pos] ->
        distance = end_pos.odometer - start_pos.odometer

        attrs = %{
          start_position_id: start_pos.id,
          end_position_id: end_pos.id,
          outside_temp_avg: end_pos.outside_temp_avg,
          inside_temp_avg: end_pos.inside_temp_avg,
          speed_max: end_pos.speed_max,
          power_max: end_pos.power_max,
          power_min: end_pos.power_min,
          power_avg: end_pos.power_avg,
          end_date: end_pos.date,
          start_km: start_pos.odometer,
          end_km: end_pos.odometer,
          start_ideal_range_km: start_pos.ideal_battery_range_km,
          end_ideal_range_km: end_pos.ideal_battery_range_km,
          start_rated_range_km: start_pos.rated_battery_range_km,
          end_rated_range_km: end_pos.rated_battery_range_km,
          duration_min: round(DateTime.diff(end_pos.date, start_pos.date) / 60),
          distance: distance
        }

        if distance < 0.01 do
          drive |> Drive.changeset(attrs) |> Repo.delete()
        else
          attrs =
            attrs
            |> put_address(:start_address_id, start_pos)
            |> put_address(:end_address_id, end_pos)
            |> put_geofence(:start_geofence_id, start_pos)
            |> put_geofence(:end_geofence_id, end_pos)

          drive |> Drive.changeset(attrs) |> Repo.update()
        end
    end
  end

  defp put_address(attrs, key, position) do
    case Locations.find_address(position) do
      {:ok, %Locations.Address{id: id}} ->
        Map.put(attrs, key, id)

      {:error, reason} ->
        Logger.warn("Address not found: #{inspect(reason)}")
        attrs
    end
  end

  defp put_geofence(attrs, key, position) do
    case Locations.find_geofence(position) do
      %Locations.GeoFence{id: id} -> Map.put(attrs, key, id)
      nil -> attrs
    end
  end

  alias TeslaMate.Log.{ChargingProcess, Charge}

  def start_charging_process(car_id, %{latitude: _, longitude: _} = position_attrs, opts \\ []) do
    position = Map.put(position_attrs, :car_id, car_id)

    address_id =
      case Locations.find_address(position) do
        {:ok, %Locations.Address{id: id}} ->
          id

        {:error, reason} ->
          Logger.warn("Address not found: #{inspect(reason)}")
          nil
      end

    geofence_id =
      with %Locations.GeoFence{id: id} <- Locations.find_geofence(position) do
        id
      end

    start_date = Keyword.get_lazy(opts, :date, &DateTime.utc_now/0)

    with {:ok, %ChargingProcess{id: id}} <-
           %ChargingProcess{car_id: car_id, address_id: address_id, geofence_id: geofence_id}
           |> ChargingProcess.changeset(%{start_date: start_date, position: position})
           |> Repo.insert() do
      {:ok, id}
    end
  end

  def insert_charge(process_id, attrs) do
    %Charge{charging_process_id: process_id}
    |> Charge.changeset(attrs)
    |> Repo.insert()
  end

  def resume_charging_process(process_id) do
    ChargingProcess
    |> preload([:car, :position])
    |> Repo.get!(process_id)
    |> ChargingProcess.changeset(%{
      end_date: nil,
      charge_energy_added: nil,
      end_ideal_range_km: nil,
      end_rated_range_km: nil,
      end_battery_level: nil,
      duration_min: nil,
      charge_energy_used: nil,
      charge_energy_used_confidence: nil
    })
    |> Repo.update()
  end

  def complete_charging_process(process_id, opts \\ []) do
    charging_process =
      ChargingProcess
      |> preload([:car, :position])
      |> Repo.get!(process_id)

    settings = Settings.get_settings!()

    charging_interval = Keyword.get(opts, :charging_interval)
    charge_energy_used_confidence = calculate_confidence(process_id, charging_interval)

    stats =
      Charge
      |> where(charging_process_id: ^process_id)
      |> select([c], %{
        charge_energy_added: max(c.charge_energy_added) - min(c.charge_energy_added),
        charge_energy_used:
          sum(
            c_if is_nil(c.charger_phases) do
              c.charger_power
            else
              c.charger_actual_current * c.charger_voltage *
                c_if(c.charger_phases == 2, do: 3, else: c.charger_phases) / 1000.0
            end
          ) * ^charging_interval / 3600,
        start_ideal_range_km: min(c.ideal_battery_range_km),
        end_ideal_range_km: max(c.ideal_battery_range_km),
        start_rated_range_km: min(c.rated_battery_range_km),
        end_rated_range_km: max(c.rated_battery_range_km),
        start_battery_level: min(c.battery_level),
        end_battery_level: max(c.battery_level),
        outside_temp_avg: avg(c.outside_temp),
        duration_min: duration_min(max(c.date), min(c.date))
      })
      |> Repo.one()
      |> Map.put(:end_date, Keyword.get_lazy(opts, :date, &DateTime.utc_now/0))
      |> Map.put(:charge_energy_used_confidence, charge_energy_used_confidence)
      |> Map.put(:interval_sec, charging_interval)

    with {:ok, cproc} <- charging_process |> ChargingProcess.changeset(stats) |> Repo.update(),
         {:ok, _car} <- recalculate_efficiency(charging_process.car, settings) do
      {:ok, cproc}
    end
  end

  defp calculate_confidence(_process_id, nil), do: nil

  defp calculate_confidence(process_id, charging_interval) do
    {:ok, %{rows: [[confidence]]}} =
      Repo.query(
        """
        WITH deltas AS (
          SELECT
            date - lag(date, 1) OVER (ORDER BY date) as delta
          FROM
            charges
          WHERE
            charging_process_id = $1
          ORDER BY
            date
        )
        SELECT
          (NULLIF(count(*), 0) / NULLIF((select count(*) from deltas)::numeric, 0))::float as confidence
        FROM
          deltas
        WHERE
          delta >= $2 * INTERVAL '1 second' and delta <= ($2 + 1) * INTERVAL '1 second';
        """,
        [process_id, charging_interval]
      )

    confidence
  end

  defp recalculate_efficiency(car, settings, opts \\ [{5, 8}, {4, 5}, {3, 3}, {2, 2}])
  defp recalculate_efficiency(car, _settings, []), do: {:ok, car}

  defp recalculate_efficiency(%Car{id: id} = car, settings, [{precision, threshold} | opts]) do
    {start_range, end_range} =
      case settings do
        %Settings.Settings{preferred_range: :ideal} ->
          {:start_ideal_range_km, :end_ideal_range_km}

        %Settings.Settings{preferred_range: :rated} ->
          {:start_rated_range_km, :end_rated_range_km}
      end

    query =
      from c in ChargingProcess,
        select: {
          round(
            c.charge_energy_added / nullif(field(c, ^end_range) - field(c, ^start_range), 0),
            ^precision
          ),
          count()
        },
        where:
          c.car_id == ^id and c.duration_min > 10 and c.end_battery_level <= 95 and
            not is_nil(field(c, ^end_range)) and not is_nil(field(c, ^start_range)),
        group_by: 1,
        order_by: [desc: 2],
        limit: 1

    case Repo.one(query) do
      {factor, n} when n >= threshold and not is_nil(factor) ->
        Logger.info("Derived efficiency factor: #{factor} Wh/km (#{n}x confirmed)", car_id: id)

        car
        |> Car.changeset(%{efficiency: factor})
        |> Repo.update()

      _ ->
        recalculate_efficiency(car, settings, opts)
    end
  end

  alias TeslaMate.Log.Update

  def start_update(car_id) do
    with {:ok, %Update{id: id}} <-
           %Update{car_id: car_id}
           |> Update.changeset(%{start_date: DateTime.utc_now()})
           |> Repo.insert() do
      {:ok, id}
    end
  end

  def cancel_update(update_id) do
    Update
    |> Repo.get!(update_id)
    |> Repo.delete()
  end

  def finish_update(update_id, version) do
    Update
    |> Repo.get!(update_id)
    |> Update.changeset(%{end_date: DateTime.utc_now(), version: version})
    |> Repo.update()
  end
end
