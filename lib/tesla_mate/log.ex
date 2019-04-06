defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  import Ecto.Query, warn: false
  import __MODULE__.Functions, only: [duration_min: 2]

  alias TeslaMate.Repo

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

  def update_car(%Car{} = car, attrs) do
    car
    |> Car.changeset(attrs)
    |> Repo.update()
  end

  ## State

  alias TeslaMate.Log.State

  def start_state(car_id, state) do
    case get_current_state(car_id) do
      %State{state: ^state} ->
        :ok

      %State{} = s ->
        with {:ok, _} <- s |> State.changeset(%{end_date: DateTime.utc_now()}) |> Repo.update(),
             {:ok, _} <- create_state(car_id, %{state: state, start_date: DateTime.utc_now()}) do
          :ok
        end

      nil ->
        with {:ok, _} <- create_state(car_id, %{state: state, start_date: DateTime.utc_now()}) do
          :ok
        end
    end
  end

  defp get_current_state(car_id) do
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
    with {:ok, _} <-
           %Position{car_id: car_id, trip_id: Map.get(attrs, :trip_id)}
           |> Position.changeset(attrs)
           |> Repo.insert() do
      :ok
    end
  end

  ## Trip

  alias TeslaMate.Log.Trip

  def start_trip(car_id) do
    with {:ok, %Trip{id: id}} <-
           %Trip{car_id: car_id}
           |> Trip.changeset(%{start_date: DateTime.utc_now()})
           |> Repo.insert() do
      {:ok, id}
    end
  end

  def close_trip(trip_id) do
    # TODO
    # :start_address
    # :end_address

    trip =
      Trip
      |> preload([:car])
      |> Repo.get!(trip_id)

    stats =
      Position
      |> where(trip_id: ^trip_id)
      |> select([p], %{
        end_date: max(p.date),
        outside_temp_avg: avg(p.outside_temp),
        speed_max: max(p.speed),
        power_max: max(p.power),
        power_min: min(p.power),
        power_avg: avg(p.power),
        start_km: min(p.odometer),
        end_km: max(p.odometer),
        distance: max(p.odometer) - min(p.odometer),
        start_range_km: min(p.ideal_battery_range_km),
        end_range_km: max(p.ideal_battery_range_km),
        duration_min: duration_min(max(p.date), min(p.date))
      })
      |> Repo.one()

    consumption = (stats.end_range_km - stats.start_range_km) * trip.car.efficiency
    consumption_100km = if(stats.distance > 0, do: consumption / stats.distance * 100, else: nil)

    stats =
      stats
      |> Map.put(:consumption_kWh, consumption)
      |> Map.put(:consumption_kWh_100km, consumption_100km)

    trip = Trip.changeset(trip, stats)

    if stats.distance == 0 do
      Repo.delete(trip)
    else
      Repo.update(trip)
    end
  end

  alias TeslaMate.Log.{ChargingProcess, Charge}

  def start_charging_process(car_id, position_attrs) do
    position = Map.put(position_attrs, :car_id, car_id)

    with {:ok, %ChargingProcess{id: id}} <-
           %ChargingProcess{car_id: car_id}
           |> ChargingProcess.changeset(%{start_date: DateTime.utc_now(), position: position})
           |> Repo.insert() do
      {:ok, id}
    end
  end

  def insert_charge(process_id, attrs) do
    with {:ok, _} <-
           %Charge{charging_process_id: process_id}
           |> Charge.changeset(attrs)
           |> Repo.insert() do
      :ok
    end
  end

  def close_charging_process(process_id) do
    charging_process =
      ChargingProcess
      |> preload([:car, :position])
      |> Repo.get!(process_id)

    stats =
      Charge
      |> where(charging_process_id: ^process_id)
      |> select([c], %{
        charge_energy_added: max(c.charge_energy_added),
        start_soc: min(c.ideal_battery_range_km),
        end_soc: max(c.ideal_battery_range_km),
        start_battery_level: min(c.battery_level),
        end_battery_level: max(c.battery_level),
        outside_temp_avg: avg(c.outside_temp),
        duration_min: duration_min(max(c.date), min(c.date))
      })
      |> Repo.one()
      |> Map.put(:end_date, DateTime.utc_now())

    calculated_max_range =
      if stats.end_battery_level > 0,
        do: round(stats.end_soc / stats.end_battery_level * 100),
        else: nil

    stats = Map.put(stats, :calculated_max_range, calculated_max_range)

    charging_process
    |> ChargingProcess.changeset(stats)
    |> Repo.update()
  end
end
