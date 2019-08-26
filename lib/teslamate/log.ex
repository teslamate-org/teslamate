defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  require Logger

  import Ecto.Query, warn: false
  import __MODULE__.Functions, only: [duration_min: 2]

  alias TeslaMate.{Repo, Locations}

  ## Car

  alias TeslaMate.Log.Car

  def list_cars do
    Repo.all(Car)
  end

  def get_car!(id) do
    Repo.get!(Car, id)
  end

  def get_car_by_eid(eid) do
    Repo.get_by(Car, eid: eid)
  end

  def create_car(%{eid: eid, vid: vid} = attrs) do
    %Car{eid: eid, vid: vid}
    |> Car.changeset(attrs)
    |> Repo.insert()
  end

  def create_or_update_car(%Ecto.Changeset{} = changeset) do
    Repo.insert_or_update(changeset)
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

  def insert_position(car_id, attrs) do
    %Position{car_id: car_id, drive_id: Map.get(attrs, :drive_id)}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  def get_latest_position(car_id) do
    Position
    |> where(car_id: ^car_id)
    |> order_by(desc: :date)
    |> limit(1)
    |> Repo.one()
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
        date: p.date,
        latitude: p.latitude,
        longitude: p.longitude,
        odometer: p.odometer,
        ideal_battery_range_km: p.ideal_battery_range_km,
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
        ideal_distance = start_pos.ideal_battery_range_km - end_pos.ideal_battery_range_km
        efficiency = if ideal_distance > 0, do: distance / ideal_distance, else: nil

        attrs = %{
          outside_temp_avg: end_pos.outside_temp_avg,
          inside_temp_avg: end_pos.inside_temp_avg,
          speed_max: end_pos.speed_max,
          power_max: end_pos.power_max,
          power_min: end_pos.power_min,
          power_avg: end_pos.power_avg,
          end_date: end_pos.date,
          start_km: start_pos.odometer,
          end_km: end_pos.odometer,
          start_range_km: start_pos.ideal_battery_range_km,
          end_range_km: end_pos.ideal_battery_range_km,
          duration_min: round(DateTime.diff(end_pos.date, start_pos.date) / 60),
          distance: distance,
          efficiency: efficiency
        }

        if distance < 0.1 do
          drive |> Drive.changeset(attrs) |> Repo.delete()
        else
          attrs =
            attrs
            |> put_address(:start_address_id, start_pos)
            |> put_address(:end_address_id, end_pos)

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

    start_date = Keyword.get_lazy(opts, :date, &DateTime.utc_now/0)

    with {:ok, %ChargingProcess{id: id}} <-
           %ChargingProcess{car_id: car_id, address_id: address_id}
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
      end_range_km: nil,
      end_battery_level: nil,
      duration_min: nil,
      calculated_max_range: nil
    })
    |> Repo.update()
  end

  def complete_charging_process(process_id, opts \\ []) do
    charging_process =
      ChargingProcess
      |> preload([:car, :position])
      |> Repo.get!(process_id)

    stats =
      Charge
      |> where(charging_process_id: ^process_id)
      |> select([c], %{
        charge_energy_added: max(c.charge_energy_added) - min(c.charge_energy_added),
        start_range_km: min(c.ideal_battery_range_km),
        end_range_km: max(c.ideal_battery_range_km),
        start_battery_level: min(c.battery_level),
        end_battery_level: max(c.battery_level),
        outside_temp_avg: avg(c.outside_temp),
        duration_min: duration_min(max(c.date), min(c.date))
      })
      |> Repo.one()
      |> Map.put(:end_date, Keyword.get_lazy(opts, :date, &DateTime.utc_now/0))

    stats = Map.put(stats, :calculated_max_range, max_range(stats))

    charging_process
    |> ChargingProcess.changeset(stats)
    |> Repo.update()
  end

  defp max_range(%{end_range_km: nil}), do: nil
  defp max_range(%{end_battery_level: nil}), do: nil
  defp max_range(%{end_range_km: range, end_battery_level: lvl}), do: round(range / lvl * 100)

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
