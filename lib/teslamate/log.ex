defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  require Logger

  import TeslaMate.CustomExpressions
  import Ecto.Query, warn: false

  alias TeslaMate.{Repo, Locations, Mapping, Settings}
  alias TeslaMate.Locations.GeoFence

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
      from p in Position,
        select: %{
          count: count() |> over(:w),
          start_position_id: first_value(p.id) |> over(:w),
          end_position_id: last_value(p.id) |> over(:w),
          outside_temp_avg: avg(p.outside_temp) |> over(:w),
          inside_temp_avg: avg(p.inside_temp) |> over(:w),
          speed_max: max(p.speed) |> over(:w),
          power_max: max(p.power) |> over(:w),
          power_min: min(p.power) |> over(:w),
          power_avg: avg(p.power) |> over(:w),
          end_date: last_value(p.date) |> over(:w),
          start_km: first_value(p.odometer) |> over(:w),
          end_km: last_value(p.odometer) |> over(:w),
          start_ideal_range_km: first_value(p.ideal_battery_range_km) |> over(:w),
          end_ideal_range_km: last_value(p.ideal_battery_range_km) |> over(:w),
          start_rated_range_km: first_value(p.rated_battery_range_km) |> over(:w),
          end_rated_range_km: last_value(p.rated_battery_range_km) |> over(:w),
          distance: (last_value(p.odometer) |> over(:w)) - (first_value(p.odometer) |> over(:w)),
          duration_min:
            fragment(
              "round(extract(epoch from (? - ?)) / 60)::integer",
              last_value(p.date) |> over(:w),
              first_value(p.date) |> over(:w)
            )
        },
        windows: [
          w: [
            order_by:
              fragment("? RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING", p.date)
          ]
        ],
        where: [drive_id: ^drive_id],
        limit: 1

    case Repo.one(query) do
      %{count: count, distance: distance} = attrs when count >= 2 and distance >= 0.01 ->
        start_pos = Repo.get!(Position, attrs.start_position_id)
        end_pos = Repo.get!(Position, attrs.end_position_id)

        attrs =
          attrs
          |> put_address(:start_address_id, start_pos)
          |> put_address(:end_address_id, end_pos)
          |> put_geofence(:start_geofence_id, start_pos)
          |> put_geofence(:end_geofence_id, end_pos)

        drive
        |> Drive.changeset(attrs)
        |> Repo.update()

      _ ->
        drive
        |> Drive.changeset(%{distance: 0, duration_min: 0})
        |> Repo.delete()
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
      %GeoFence{id: id} -> Map.put(attrs, key, id)
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
      with %GeoFence{id: id} <- Locations.find_geofence(position) do
        id
      end

    start_date = Keyword.get_lazy(opts, :date, &DateTime.utc_now/0)

    with {:ok, cproc} <-
           %ChargingProcess{car_id: car_id, address_id: address_id, geofence_id: geofence_id}
           |> ChargingProcess.changeset(%{start_date: start_date, position: position})
           |> Repo.insert() do
      {:ok, Repo.preload(cproc, [:address, :geofence])}
    end
  end

  def insert_charge(%ChargingProcess{id: id}, attrs) do
    %Charge{charging_process_id: id}
    |> Charge.changeset(attrs)
    |> Repo.insert()
  end

  def complete_charging_process(%ChargingProcess{} = charging_process) do
    charging_process = Repo.preload(charging_process, [:car])

    settings = Settings.get_settings!()

    stats =
      from(c in Charge,
        select: %{
          start_ideal_range_km: first_value(c.ideal_battery_range_km) |> over(:w),
          end_ideal_range_km: last_value(c.ideal_battery_range_km) |> over(:w),
          start_rated_range_km: first_value(c.rated_battery_range_km) |> over(:w),
          end_rated_range_km: last_value(c.rated_battery_range_km) |> over(:w),
          start_battery_level: first_value(c.battery_level) |> over(:w),
          end_battery_level: last_value(c.battery_level) |> over(:w),
          outside_temp_avg: avg(c.outside_temp) |> over(:w),
          charge_energy_added:
            (last_value(c.charge_energy_added) |> over(:w)) -
              (first_value(c.charge_energy_added) |> over(:w)),
          duration_min:
            duration_min(last_value(c.date) |> over(:w), first_value(c.date) |> over(:w))
        },
        windows: [
          w: [
            order_by:
              fragment("? RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING", c.date)
          ]
        ],
        where: [charging_process_id: ^charging_process.id],
        limit: 1
      )
      |> Repo.one() || %{}

    charge_energy_used = calculate_energy_used(charging_process)

    attrs =
      stats
      |> Map.put(:end_date, charging_process.end_date || DateTime.utc_now())
      |> Map.put(:charge_energy_used, charge_energy_used)
      |> Map.update(:charge_energy_added, nil, &if(&1 < 0, do: nil, else: &1))

    with {:ok, cproc} <- charging_process |> ChargingProcess.changeset(attrs) |> Repo.update(),
         {:ok, _car} <- recalculate_efficiency(charging_process.car, settings) do
      {:ok, cproc}
    end
  end

  def update_energy_used(%ChargingProcess{} = charging_process) do
    charging_process
    |> ChargingProcess.changeset(%{charge_energy_used: calculate_energy_used(charging_process)})
    |> Repo.update()
  end

  defp calculate_energy_used(%ChargingProcess{id: id}) do
    query =
      from c in Charge,
        join: p in ChargingProcess,
        on: [id: c.charging_process_id],
        full_join: g in GeoFence,
        on: [id: p.geofence_id],
        select: %{
          energy_used:
            c_if is_nil(c.charger_phases) do
              c.charger_power
            else
              c.charger_actual_current * c.charger_voltage *
                coalesce(g.phase_correction, c.charger_phases) /
                1000.0
            end *
              fragment(
                "EXTRACT(epoch FROM (?))",
                c.date - (lag(c.date) |> over(order_by: c.date))
              ) / 3600
        },
        where: c.charging_process_id == ^id

    from(e in subquery(query),
      select: {sum(e.energy_used)},
      where: e.energy_used > 0
    )
    |> Repo.one()
    |> case do
      {charge_energy_used} -> charge_energy_used
      _ -> nil
    end
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
        Logger.info("Derived efficiency factor: #{factor * 1000} Wh/km (#{n}x confirmed)",
          car_id: id
        )

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
