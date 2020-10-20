defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  require Logger

  import TeslaMate.CustomExpressions
  import Ecto.Query, warn: false

  alias __MODULE__.{Car, Drive, Update, ChargingProcess, Charge, Position, State}
  alias TeslaMate.{Repo, Locations, Settings}
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Settings.{CarSettings, GlobalSettings}

  ## Car

  def list_cars do
    Repo.all(Car)
  end

  def get_car!(id) do
    Repo.get!(Car, id)
  end

  def get_car_by([{_key, nil}]), do: nil
  def get_car_by([{_key, _val}] = opts), do: Repo.get_by(Car, opts)

  def create_car(attrs) do
    %Car{settings: %CarSettings{}}
    |> Car.changeset(attrs)
    |> Repo.insert()
  end

  def create_or_update_car(%Ecto.Changeset{} = changeset) do
    with {:ok, car} <- Repo.insert_or_update(changeset) do
      {:ok, Repo.preload(car, [:settings])}
    end
  end

  def update_car(%Car{} = car, attrs, opts \\ []) do
    with {:ok, car} <- car |> Car.changeset(attrs) |> Repo.update() do
      preloads = Keyword.get(opts, :preload, [])
      {:ok, Repo.preload(car, preloads, force: true)}
    end
  end

  def recalculate_efficiencies(%GlobalSettings{} = settings) do
    for car <- list_cars() do
      {:ok, _car} = recalculate_efficiency(car, settings)
    end

    :ok
  end

  ## State

  def start_state(%Car{} = car, state, opts \\ []) when not is_nil(state) do
    now = Keyword.get(opts, :date) || DateTime.utc_now()

    case get_current_state(car) do
      %State{state: ^state} = s ->
        {:ok, s}

      %State{} = s ->
        Repo.transaction(fn ->
          with {:ok, _} <- s |> State.changeset(%{end_date: now}) |> Repo.update(),
               {:ok, new_state} <- create_state(car, %{state: state, start_date: now}) do
            new_state
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      nil ->
        create_state(car, %{state: state, start_date: now})
    end
  end

  def get_current_state(%Car{id: id}) do
    State
    |> where([s], ^id == s.car_id and is_nil(s.end_date))
    |> Repo.one()
  end

  def create_current_state(%Car{id: id} = car) do
    query =
      from s in State,
        where: s.car_id == ^id,
        order_by: [desc: s.start_date],
        limit: 1

    with nil <- get_current_state(car),
         %State{} = state <- Repo.one(query),
         {:ok, _} <- state |> State.changeset(%{end_date: nil}) |> Repo.update() do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  def complete_current_state(%Car{id: id} = car) do
    case get_current_state(car) do
      %State{start_date: date} = state ->
        query =
          from s in State,
            where: s.car_id == ^id and s.start_date > ^date,
            order_by: [asc: s.start_date],
            limit: 1

        end_date =
          case Repo.one(query) do
            %State{start_date: d} -> d
            nil -> DateTime.add(date, 1, :second)
          end

        with {:ok, _} <-
               state
               |> State.changeset(%{end_date: end_date})
               |> Repo.update() do
          :ok
        end

      nil ->
        :ok
    end
  end

  def get_earliest_state(%Car{id: id}) do
    State
    |> where(car_id: ^id)
    |> order_by(asc: :start_date)
    |> limit(1)
    |> Repo.one()
  end

  defp create_state(%Car{id: id}, attrs) do
    %State{car_id: id}
    |> State.changeset(attrs)
    |> Repo.insert()
  end

  ## Position

  def insert_position(%Drive{id: id, car_id: car_id}, attrs) do
    %Position{car_id: car_id, drive_id: id}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  def insert_position(%Car{id: id}, attrs) do
    %Position{car_id: id}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  def get_latest_position do
    Position
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
  end

  def get_latest_position(%Car{id: id}) do
    Position
    |> where(car_id: ^id)
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
  end

  def get_positions_without_elevation(min_id \\ 0, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    non_streamed_drives =
      Repo.all(
        from d in subquery(
               from p in Position,
                 select: %{
                   drive_id: p.drive_id,
                   streamed_count:
                     count()
                     |> filter(not is_nil(p.odometer) and is_nil(p.ideal_battery_range_km))
                 },
                 where: not is_nil(p.drive_id),
                 group_by: p.drive_id
             ),
             select: d.drive_id,
             where: d.streamed_count == 0
      )

    Position
    |> where([p], p.id > ^min_id and is_nil(p.elevation) and p.drive_id in ^non_streamed_drives)
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

  def start_drive(%Car{id: id}) do
    %Drive{car_id: id}
    |> Drive.changeset(%{start_date: DateTime.utc_now()})
    |> Repo.insert()
  end

  def close_drive(%Drive{id: id} = drive, opts \\ []) do
    drive = Repo.preload(drive, [:car])

    drive_data =
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
          start_date: first_value(p.date) |> over(:w),
          end_date: last_value(p.date) |> over(:w),
          start_km: first_value(p.odometer) |> over(:w),
          end_km: last_value(p.odometer) |> over(:w),
          distance: (last_value(p.odometer) |> over(:w)) - (first_value(p.odometer) |> over(:w)),
          duration_min:
            fragment(
              "round(extract(epoch from (? - ?)) / 60)::integer",
              last_value(p.date) |> over(:w),
              first_value(p.date) |> over(:w)
            ),
          start_ideal_range_km: -1,
          end_ideal_range_km: -1,
          start_rated_range_km: -1,
          end_rated_range_km: -1
        },
        windows: [
          w: [
            order_by:
              fragment("? RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING", p.date)
          ]
        ],
        where: p.drive_id == ^id,
        limit: 1

    non_streamed_drive_data =
      from p in Position,
        select: %{
          start_ideal_range_km: first_value(p.ideal_battery_range_km) |> over(:w),
          end_ideal_range_km: last_value(p.ideal_battery_range_km) |> over(:w),
          start_rated_range_km: first_value(p.rated_battery_range_km) |> over(:w),
          end_rated_range_km: last_value(p.rated_battery_range_km) |> over(:w)
        },
        windows: [
          w: [
            order_by:
              fragment("? RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING", p.date)
          ]
        ],
        where:
          p.drive_id == ^id and
            not is_nil(p.ideal_battery_range_km) and
            not is_nil(p.odometer),
        limit: 1

    query =
      from d0 in subquery(drive_data),
        join: d1 in subquery(non_streamed_drive_data),
        select: %{
          d0
          | start_ideal_range_km: d1.start_ideal_range_km,
            end_ideal_range_km: d1.end_ideal_range_km,
            start_rated_range_km: d1.start_rated_range_km,
            end_rated_range_km: d1.end_rated_range_km
        }

    case Repo.one(query) do
      %{count: count, distance: distance} = attrs when count >= 2 and distance >= 0.01 ->
        lookup_address = Keyword.get(opts, :lookup_address, true)

        start_pos = Repo.get!(Position, attrs.start_position_id)
        end_pos = Repo.get!(Position, attrs.end_position_id)

        attrs =
          if lookup_address do
            attrs
            |> put_address(:start_address_id, start_pos)
            |> put_address(:end_address_id, end_pos)
          else
            attrs
          end

        attrs =
          attrs
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
        Logger.warning("Address not found: #{inspect(reason)}")
        attrs
    end
  end

  defp put_geofence(attrs, key, position) do
    case Locations.find_geofence(position) do
      %GeoFence{id: id} -> Map.put(attrs, key, id)
      nil -> attrs
    end
  end

  ## ChargingProcess

  def get_charging_process!(id) do
    ChargingProcess
    |> where(id: ^id)
    |> preload([:address, :geofence, :car, :position])
    |> Repo.one!()
  end

  def update_charging_process(%ChargingProcess{} = charge, attrs) do
    charge
    |> ChargingProcess.changeset(attrs)
    |> Repo.update()
  end

  def start_charging_process(%Car{id: id}, %{latitude: _, longitude: _} = attrs, opts \\ []) do
    lookup_address = Keyword.get(opts, :lookup_address, true)
    position = Map.put(attrs, :car_id, id)

    address_id =
      if lookup_address do
        case Locations.find_address(position) do
          {:ok, %Locations.Address{id: id}} ->
            id

          {:error, reason} ->
            Logger.warning("Address not found: #{inspect(reason)}")
            nil
        end
      end

    geofence_id =
      with %GeoFence{id: id} <- Locations.find_geofence(position) do
        id
      end

    with {:ok, cproc} <-
           %ChargingProcess{car_id: id, address_id: address_id, geofence_id: geofence_id}
           |> ChargingProcess.changeset(%{start_date: DateTime.utc_now(), position: position})
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
    charging_process = Repo.preload(charging_process, [{:car, :settings}, :geofence])
    settings = Settings.get_global_settings!()

    type =
      from(c in Charge,
        select: %{
          fast_charger_type: fragment("mode() WITHIN GROUP (ORDER BY ?)", c.fast_charger_type)
        },
        where: c.charging_process_id == ^charging_process.id and c.charger_power > 0
      )

    stats =
      from(c in Charge,
        join: t in subquery(type),
        on: true,
        select: %{
          start_date: first_value(c.date) |> over(:w),
          end_date: last_value(c.date) |> over(:w),
          start_ideal_range_km: first_value(c.ideal_battery_range_km) |> over(:w),
          end_ideal_range_km: last_value(c.ideal_battery_range_km) |> over(:w),
          start_rated_range_km: first_value(c.rated_battery_range_km) |> over(:w),
          end_rated_range_km: last_value(c.rated_battery_range_km) |> over(:w),
          start_battery_level: first_value(c.battery_level) |> over(:w),
          end_battery_level: last_value(c.battery_level) |> over(:w),
          outside_temp_avg: avg(c.outside_temp) |> over(:w),
          charge_energy_added:
            coalesce(
              nullif(last_value(c.charge_energy_added) |> over(:w), 0),
              max(c.charge_energy_added) |> over(:w)
            ) -
              (first_value(c.charge_energy_added) |> over(:w)),
          duration_min:
            duration_min(last_value(c.date) |> over(:w), first_value(c.date) |> over(:w)),
          fast_charger_type: t.fast_charger_type
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
      |> Repo.one() || %{end_date: DateTime.utc_now(), charge_energy_added: nil}

    charge_energy_used = calculate_energy_used(charging_process)

    attrs =
      stats
      |> Map.put(:charge_energy_used, charge_energy_used)
      |> Map.update(:charge_energy_added, nil, fn kwh ->
        cond do
          kwh == nil or Decimal.negative?(kwh) -> nil
          true -> kwh
        end
      end)
      |> put_cost(charging_process)

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

  defp calculate_energy_used(%ChargingProcess{id: id} = charging_process) do
    phases = determine_phases(charging_process)

    query =
      from c in Charge,
        select: %{
          energy_used:
            c_if is_nil(c.charger_phases) do
              c.charger_power
            else
              c.charger_actual_current * c.charger_voltage * type(^phases, :float) / 1000.0
            end *
              fragment(
                "EXTRACT(epoch FROM (?))",
                c.date - (lag(c.date) |> over(order_by: c.date))
              ) / 3600
        },
        where: c.charging_process_id == ^id

    Repo.one(
      from e in subquery(query),
        select: sum(e.energy_used) |> type(:decimal),
        where: e.energy_used >= 0
    )
  end

  defp determine_phases(%ChargingProcess{id: id, car_id: car_id}) do
    from(c in Charge,
      select: {
        avg(c.charger_power * 1000.0 / nullif(c.charger_actual_current * c.charger_voltage, 0))
        |> type(:float),
        avg(c.charger_phases) |> type(:integer),
        avg(c.charger_voltage) |> type(:float),
        count()
      },
      group_by: c.charging_process_id,
      where: c.charging_process_id == ^id
    )
    |> Repo.one()
    |> case do
      {p, r, v, n} when not is_nil(p) and p > 0 and n > 15 ->
        cond do
          r == round(p) ->
            r

          r == 3 and abs(p / :math.sqrt(r) - 1) <= 0.1 ->
            Logger.info("Voltage correction: #{round(v)}V -> #{round(v / :math.sqrt(r))}V",
              car_id: car_id
            )

            :math.sqrt(r)

          abs(round(p) - p) <= 0.3 ->
            Logger.info("Phase correction: #{r} -> #{round(p)}", car_id: car_id)
            round(p)

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  defp put_cost(stats, %ChargingProcess{} = charging_process) do
    alias ChargingProcess, as: CP

    cost =
      case {stats, charging_process} do
        {%{fast_charger_type: "Tesla" <> _},
         %CP{car: %Car{settings: %CarSettings{free_supercharging: true}}}} ->
          0.0

        {%{charge_energy_used: kwh_used, charge_energy_added: kwh_added},
         %CP{
           geofence: %GeoFence{
             billing_type: :per_kwh,
             cost_per_unit: cost_per_kwh,
             session_fee: session_fee
           }
         }} ->
          if match?(%Decimal{}, kwh_used) or match?(%Decimal{}, kwh_added) do
            cost =
              with %Decimal{} <- cost_per_kwh do
                [kwh_added, kwh_used]
                |> Enum.reject(&is_nil/1)
                |> Enum.max(Decimal)
                |> Decimal.mult(cost_per_kwh)
              end

            if match?(%Decimal{}, cost) or match?(%Decimal{}, session_fee) do
              Decimal.add(session_fee || 0, cost || 0)
            end
          end

        {%{duration_min: minutes},
         %CP{
           geofence: %GeoFence{
             billing_type: :per_minute,
             cost_per_unit: cost_per_minute,
             session_fee: session_fee
           }
         }}
        when is_number(minutes) ->
          cost = Decimal.mult(minutes, cost_per_minute)

          if match?(%Decimal{}, cost) or match?(%Decimal{}, session_fee) do
            Decimal.add(session_fee || 0, cost || 0)
          end

        {_, _} ->
          nil
      end

    Map.put(stats, :cost, cost)
  end

  defp recalculate_efficiency(car, settings, opts \\ [{5, 8}, {4, 5}, {3, 3}, {2, 2}])
  defp recalculate_efficiency(car, _settings, []), do: {:ok, car}

  defp recalculate_efficiency(%Car{id: id} = car, settings, [{precision, threshold} | opts]) do
    {start_range, end_range} =
      case settings do
        %GlobalSettings{preferred_range: :ideal} ->
          {:start_ideal_range_km, :end_ideal_range_km}

        %GlobalSettings{preferred_range: :rated} ->
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
            not is_nil(field(c, ^end_range)) and not is_nil(field(c, ^start_range)) and
            c.charge_energy_added > 0.0,
        group_by: 1,
        order_by: [desc: 2],
        limit: 1

    case Repo.one(query) do
      {factor, n} when n >= threshold and not is_nil(factor) and factor > 0 ->
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

  ## Update

  def start_update(%Car{id: id}, opts \\ []) do
    start_date = Keyword.get(opts, :date) || DateTime.utc_now()

    %Update{car_id: id}
    |> Update.changeset(%{start_date: start_date})
    |> Repo.insert()
  end

  def cancel_update(%Update{} = update) do
    Repo.delete(update)
  end

  def finish_update(%Update{} = update, version, opts \\ []) do
    end_date = Keyword.get(opts, :date) || DateTime.utc_now()

    update
    |> Update.changeset(%{end_date: end_date, version: version})
    |> Repo.update()
  end

  def get_latest_update(%Car{id: id}) do
    from(u in Update, where: [car_id: ^id], order_by: [desc: :start_date], limit: 1)
    |> Repo.one()
  end

  def insert_missed_update(%Car{id: id}, version, opts \\ []) do
    date = Keyword.get(opts, :date) || DateTime.utc_now()

    %Update{car_id: id}
    |> Update.changeset(%{start_date: date, end_date: date, version: version})
    |> Repo.insert()
  end
end
