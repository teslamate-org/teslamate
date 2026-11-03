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

  def list_car_ids_by_display_order do
    display_order_query()
    |> select([c], c.id)
    |> Repo.all()
  end

  def move_car(car_id, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      # Rows re-fetched after waiting on a lock may come back out of ORDER BY order
      cars =
        display_order_query()
        |> lock("FOR UPDATE")
        |> Repo.all()
        |> Enum.sort_by(&{&1.display_priority, &1.id})

      index = Enum.find_index(cars, &(&1.id == car_id)) || Repo.rollback(:not_found)
      neighbour = if direction == :up, do: index - 1, else: index + 1

      cars =
        if neighbour >= 0 and neighbour < length(cars) do
          moved =
            cars
            |> List.replace_at(index, Enum.at(cars, neighbour))
            |> List.replace_at(neighbour, Enum.at(cars, index))

          for {car, priority} <- Enum.with_index(moved, 1), car.display_priority != priority do
            {:ok, _car} = car |> Car.changeset(%{display_priority: priority}) |> Repo.update()
          end

          moved
        else
          cars
        end

      Enum.map(cars, & &1.id)
    end)
  end

  defp display_order_query do
    from(c in Car, order_by: [asc: c.display_priority, asc: c.id])
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

  # Order by id for PK scan; geofence map center only.
  def get_last_inserted_position do
    Position
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  # Filter ideal_battery_range_km so restore uses partial index, not seq scan.
  def get_latest_position(%Car{id: id}) do
    Position
    |> where([p], p.car_id == ^id and not is_nil(p.ideal_battery_range_km))
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
  end

  # The source of a position is not stored, so this is a heuristic: a position
  # with an odometer but no ideal range counts as from the stream, as the stream
  # path never stores ideal_battery_range_km. It misclassifies a poll with an
  # odometer but without ideal range as a stream position, and a stream position
  # without odometer as a poll.
  defmacrop stream_position?(position) do
    quote do
      not is_nil(unquote(position).odometer) and
        is_nil(unquote(position).ideal_battery_range_km)
    end
  end

  # The closed drives whose positions still lack terrain elevation: enqueued by
  # close_drive/1, dequeued by add_terrain_elevation/4 (see the migration).
  @terrain_elevation_queue "terrain_elevation_queue"

  # A poll of a drive with stream positions lies in a stream gap, and takes the
  # terrain elevation, once at least this many polls came since the drive's
  # last stream position or its start. Vehicle applies it at insert, in the
  # order the positions arrive (in_stream_gap?/1); terrain_elevation_positions/1
  # applies it in that order and by date.
  @stream_gap_polls 2

  def in_stream_gap?(polls_since_stream_position),
    do: polls_since_stream_position >= @stream_gap_polls

  # The drives Terrain adds the terrain elevation to: those that started in
  # the 10 days before the :now option (the current time by default), open or
  # closed, and any closed drive in the terrain_elevation_queue, whatever its
  # age. The window keeps the pass to recent drives (#4228). Each as its id,
  # end_date (a drive is closed for good, so one listed closed takes no new
  # positions while Terrain works on it) and whether it is queued. Closed
  # drives come first, those tried without completing last, longest ago
  # first: a pass ends when Terrain cannot answer, and a drive whose lookups
  # keep failing must not hold back the others. Open drives come last; once
  # closed, they are queued like any other.
  def get_terrain_elevation_drives(opts \\ []) do
    window_start =
      opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.add(-10, :day)

    from(drive in Drive,
      left_join: queued in @terrain_elevation_queue,
      on: queued.drive_id == drive.id,
      where: drive.start_date > ^window_start or not is_nil(queued.drive_id),
      order_by: [
        asc: is_nil(drive.end_date),
        asc_nulls_first: queued.attempted_at,
        asc: drive.id
      ],
      select: %{id: drive.id, end_date: drive.end_date, queued: not is_nil(queued.drive_id)}
    )
    |> Repo.all()
  end

  # The positions of the drive that take the terrain elevation but have none:
  # of a closed drive those in a stream gap by date, which is final. An open
  # drive can still take a stream position that arrives late, dated before
  # polls stored already; only a poll in a stream gap in both orders keeps its
  # terrain elevation then, as close_drive/1 removes it from the others.
  def get_positions_without_elevation(drive_id) do
    drive_id
    |> positions_without_elevation()
    |> order_by(asc: :id)
    |> Repo.all()
  end

  defp positions_without_elevation(drive_id) do
    Position
    |> join(:inner, [position], drive in assoc(position, :drive))
    |> join(:inner, [position], rule in subquery(terrain_elevation_positions(drive_id)),
      on: rule.id == position.id
    )
    |> where(
      [position, drive, rule],
      is_nil(position.elevation) and rule.in_stream_gap_by_date and
        (rule.in_stream_gap_by_arrival or not is_nil(drive.end_date))
    )
  end

  # Whether each position of the drive lies in a stream gap and takes the
  # terrain elevation, with the polls counted in the order they arrived (by
  # id), as Vehicle decides at insert, and by date (then id): the elevations
  # are a time series. Every position of a drive without stream positions does.
  defp terrain_elevation_positions(drive_id) do
    from(by_date in subquery(stream_gap_positions(drive_id, [:date, :id])),
      join: by_arrival in subquery(stream_gap_positions(drive_id, [:id])),
      on: by_arrival.id == by_date.id,
      select: %{
        id: by_date.id,
        stream_position: by_date.stream_position,
        in_stream_gap_by_date: by_date.in_stream_gap,
        in_stream_gap_by_arrival: by_arrival.in_stream_gap
      }
    )
  end

  defp stream_gap_positions(drive_id, order) do
    # Each stream position starts a segment of the drive; segment 0 is the
    # stretch before the drive's first stream position.
    segments =
      from(position in Position,
        where: position.drive_id == ^drive_id,
        windows: [ordered: [order_by: ^order]],
        select: %{
          id: position.id,
          date: position.date,
          stream_position: stream_position?(position),
          stream_positions:
            filter(count(), stream_position?(position)) |> over(partition_by: position.drive_id),
          segment: filter(count(), stream_position?(position)) |> over(:ordered)
        }
      )

    from(position in subquery(segments),
      windows: [
        preceding: [
          partition_by: position.segment,
          order_by: ^order,
          frame: ^dynamic(fragment("ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING"))
        ]
      ],
      select: %{
        id: position.id,
        stream_position: position.stream_position,
        in_stream_gap:
          position.stream_positions == 0 or
            (not position.stream_position and
               filter(count(), not position.stream_position) |> over(:preceding) >=
                 ^@stream_gap_polls)
      }
    )
  end

  ## Drive

  def start_drive(%Car{id: id}) do
    %Drive{car_id: id}
    |> Drive.changeset(%{start_date: DateTime.utc_now()})
    |> Repo.insert()
  end

  # Leaves the addresses to the caller, which looks them up outside of any
  # transaction: the lookup queries Nominatim, which takes a while. Hands
  # back the closed drive with its start and end position for that. Leaves
  # the terrain elevation its positions lack to Terrain for the same reason:
  # enqueues the drive (add_terrain_elevation/4).
  def close_drive(%Drive{id: id} = drive) do
    Repo.transaction(fn ->
      _drive = lock_drive(id)
      :ok = remove_terrain_elevation_outside_stream_gaps(id)

      case do_close_drive(drive) do
        {:ok, drive} -> drive
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_close_drive(%Drive{id: id} = drive) do
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
          end_rated_range_km: -1,
          ascent: 0,
          descent: 0
        },
        windows: [
          w: [
            order_by: p.date,
            frame: fragment("RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING")
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
            order_by: p.date,
            frame: fragment("RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING")
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
        on: true,
        join: e in subquery(elevation_data(id)),
        on: true,
        select: %{
          d0
          | start_ideal_range_km: d1.start_ideal_range_km,
            end_ideal_range_km: d1.end_ideal_range_km,
            start_rated_range_km: d1.start_rated_range_km,
            end_rated_range_km: d1.end_rated_range_km,
            ascent: e.elevation_gains,
            descent: e.elevation_losses
        }

    case Repo.one(query) do
      %{count: count, distance: distance} = attrs when count >= 2 and distance >= 0.01 ->
        start_pos = Repo.get!(Position, attrs.start_position_id)
        end_pos = Repo.get!(Position, attrs.end_position_id)

        attrs =
          attrs
          |> put_geofence(:start_geofence_id, start_pos)
          |> put_geofence(:end_geofence_id, end_pos)

        with {:ok, %Drive{} = drive} <- drive |> Drive.changeset(attrs) |> Repo.update() do
          :ok = enqueue_lacking_terrain_elevation(drive.id)
          {:ok, %Drive{drive | start_position: start_pos, end_position: end_pos}}
        end

      _ ->
        drive
        |> Drive.changeset(%{distance: 0, duration_min: 0})
        |> Repo.delete()
    end
  end

  # A closed drive waits in the queue only while positions lack the terrain
  # elevation they take; one closed with none such needs no pass.
  defp enqueue_lacking_terrain_elevation(drive_id) do
    if drive_id |> positions_without_elevation() |> Repo.exists?() do
      {_count, nil} =
        Repo.insert_all(@terrain_elevation_queue, [%{drive_id: drive_id}], on_conflict: :nothing)
    end

    :ok
  end

  # Stores the terrain elevations looked up for positions of the drive, a map
  # of position id to elevation, in one transaction with what they change: for
  # a closed drive the ascent and descent, recomputed after removing the
  # terrain elevation from polls outside a stream gap, so they match the
  # stored elevations whatever happens before or after. The status settles
  # the queue entry of a closed drive: :complete, when every position that
  # lacked elevation, read while the drive was already closed, got an answer,
  # takes the drive out; :failed, when a lookup failed, puts it there or
  # keeps it, marked as tried at the :now option (the current time by
  # default), so get_terrain_elevation_drives/1 takes it last; :incomplete,
  # when the lookups ended before failing, leaves the entry as it is. The
  # ascent and descent of an open drive are left to close_drive/1; a deleted
  # drive is left as it is.
  def add_terrain_elevation(drive_id, elevations, status, opts \\ [])
      when is_integer(drive_id) and is_map(elevations) and
             status in [:complete, :incomplete, :failed] do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    {:ok, :ok} =
      Repo.transaction(fn ->
        case lock_drive(drive_id) do
          nil -> :ok
          %Drive{} = drive -> store_terrain_elevation(drive, elevations, status, now)
        end
      end)

    :ok
  end

  defp store_terrain_elevation(%Drive{id: id, end_date: nil}, elevations, _status, _now),
    do: put_elevations(id, elevations)

  defp store_terrain_elevation(%Drive{id: id}, elevations, status, now)
       when map_size(elevations) == 0,
       do: settle_queue(id, status, now)

  defp store_terrain_elevation(%Drive{id: id}, elevations, status, now) do
    :ok = put_elevations(id, elevations)
    :ok = remove_terrain_elevation_outside_stream_gaps(id)

    {1, nil} =
      from(drive in Drive,
        join: elevation in subquery(elevation_data(id)),
        on: true,
        where: drive.id == ^id,
        update: [set: [ascent: elevation.elevation_gains, descent: elevation.elevation_losses]]
      )
      |> Repo.update_all([])

    settle_queue(id, status, now)
  end

  defp settle_queue(_drive_id, :incomplete, _now), do: :ok

  defp settle_queue(drive_id, :failed, now) do
    {1, nil} =
      Repo.insert_all(
        @terrain_elevation_queue,
        [%{drive_id: drive_id, attempted_at: now}],
        on_conflict: [set: [attempted_at: now]],
        conflict_target: :drive_id
      )

    :ok
  end

  defp settle_queue(drive_id, :complete, _now) do
    {_count, nil} =
      from(queued in @terrain_elevation_queue, where: queued.drive_id == ^drive_id)
      |> Repo.delete_all()

    :ok
  end

  # Serializes the writes that keep a closed drive's ascent and descent in line
  # with its elevations, close_drive/1 and add_terrain_elevation/4. It takes no
  # key lock, so positions are still inserted into the drive meanwhile.
  defp lock_drive(drive_id) do
    from(drive in Drive,
      where: drive.id == ^drive_id,
      lock: "FOR NO KEY UPDATE",
      select: [:id, :end_date]
    )
    |> Repo.one()
  end

  # Each row takes two of the at most 65535 parameters of a statement.
  @elevations_per_update 1000

  defp put_elevations(drive_id, elevations) do
    elevations
    |> Enum.map(fn {id, elevation} -> %{id: id, elevation: elevation} end)
    |> Enum.chunk_every(@elevations_per_update)
    |> Enum.each(fn rows ->
      {_count, nil} =
        from(position in Position,
          join: looked_up in values(rows, %{id: :id, elevation: :integer}),
          on: looked_up.id == position.id,
          where: position.drive_id == ^drive_id,
          update: [set: [elevation: looked_up.elevation]]
        )
        |> Repo.update_all([])
    end)
  end

  # A poll takes the elevation of the terrain, a stream position that of the
  # car. Vehicle decides at insert, in the order the positions arrive; a
  # stream position that arrives late can show by date that a poll it counted
  # in a stream gap lay in none. That poll's terrain elevation is removed
  # before the ascent and descent count it. A poll outside a stream gap in the
  # order of arrival too got its elevation while the car was not streaming,
  # and keeps it.
  defp remove_terrain_elevation_outside_stream_gaps(drive_id) do
    {_count, nil} =
      from(position in Position,
        join: rule in subquery(terrain_elevation_positions(drive_id)),
        on: rule.id == position.id,
        where:
          not rule.stream_position and rule.in_stream_gap_by_arrival and
            not rule.in_stream_gap_by_date and not is_nil(position.elevation),
        update: [set: [elevation: nil]]
      )
      |> Repo.update_all([])

    :ok
  end

  # If the sum of elevation gains exceeds the max value of a smallint (32767), set it to 0.
  # If the sum of elevation losses exceeds the max value of a smallint (32767), set it to 0.
  defp elevation_data(drive_id) do
    from change in subquery(
           from position in Position,
             where: position.drive_id == ^drive_id and not is_nil(position.elevation),
             select: %{
               elevation_diff:
                 position.elevation -
                   (lag(position.elevation)
                    |> over(order_by: [asc: position.date, asc: position.id]))
             }
         ),
         select: %{
           elevation_gains:
             fragment(
               "COALESCE(NULLIF(LEAST(SUM(CASE WHEN ? > 0 THEN ? ELSE 0 END), 32768), 32768), 0)",
               change.elevation_diff,
               change.elevation_diff
             ),
           elevation_losses:
             fragment(
               "COALESCE(NULLIF(LEAST(SUM(CASE WHEN ? < 0 THEN ABS(?) ELSE 0 END), 32768), 32768), 0)",
               change.elevation_diff,
               change.elevation_diff
             )
         }
  end

  defp put_geofence(attrs, key, position) do
    case Locations.find_geofence(position) do
      %GeoFence{id: id} -> Map.put(attrs, key, id)
      nil -> attrs
    end
  end

  def update_drive(%Drive{} = drive, attrs) do
    drive
    |> Drive.changeset(attrs)
    |> Repo.update()
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

  # Takes the address id from the caller, which looks it up outside of any
  # transaction: the lookup queries Nominatim, which takes a while.
  def start_charging_process(%Car{id: id}, %{latitude: _, longitude: _} = attrs, opts \\ []) do
    address_id = Keyword.get(opts, :address_id)
    position = Map.put(attrs, :car_id, id)

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
            order_by: c.date,
            frame: fragment("RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING")
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
              coalesce(
                type(^phases, :float) * c.charger_actual_current * c.charger_voltage / 1000.0,
                c.charger_power
              )
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
        avg(
          c.charger_power * 1000.0 /
            nullif(type(c.charger_actual_current, :integer) * c.charger_voltage, 0)
        )
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

          round(p) > 0 and abs(round(p) - p) <= 0.3 ->
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
          Decimal.add(session_fee || 0, cost)

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
