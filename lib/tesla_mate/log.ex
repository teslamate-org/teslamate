defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  import Ecto.Query, warn: false
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
    # TODO statistics
    attrs = %{}

    with {:ok, _trip} <-
           Trip
           |> Repo.get!(trip_id)
           |> Trip.changeset(attrs)
           |> Repo.update() do
      :ok
    end

    # statistics =
    #   Position
    #   |> select([p], %{
    #     outside_temp_avg: fragment("?::float", avg(p.outside_temp)),
    #     speed_max: max(p.speed),
    #     speed_min: min(p.speed),
    #     power_max: max(p.power),
    #     power_min: min(p.power),
    #     power_avg: fragment("?::float", avg(p.power))
    #   })
    #   |> where(
    #     [p],
    #     car_id == p.car_id and ^start_position_id <= p.id and p.id <= ^end_position_id
    #   )
    #   |> Repo.one!()
    #   |> Map.to_list()

    # result =
    #   Trip
    #   |> where(
    #     [d],
    #     car_id == d.car_id and d.start_position_id == ^start_position_id and
    #       d.end_position_id == ^end_position_id
    #   )
    #   |> update(set: ^statistics)
    #   |> Repo.update_all([])

    # case result do
    #   {0, nil} -> {:erorr, :no_trips_to_be_updated}
    #   {1, nil} -> :ok
    # end
  end

  alias TeslaMate.Log.{ChargingProcess, Charge}

  def start_charging_process(car_id) do
    # TODO remove when combined with other actions
    last_position_id =
      Position
      |> select([p], max(p.id))
      |> where(car_id: ^car_id)
      |> Repo.one!()

    with {:ok, %ChargingProcess{id: id}} <-
           %ChargingProcess{car_id: car_id, position_id: last_position_id}
           |> ChargingProcess.changeset(%{start_date: DateTime.utc_now()})
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
    # TODO calculate statistics

    with {:ok, _} <-
           ChargingProcess
           |> Repo.get!(process_id)
           |> ChargingProcess.changeset(%{end_date: DateTime.utc_now()})
           |> Repo.update() do
      :ok
    end
  end
end
