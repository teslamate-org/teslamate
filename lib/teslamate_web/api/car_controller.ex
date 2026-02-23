defmodule TeslaMateWeb.Api.CarController do
  use TeslaMateWeb, :controller

  alias TeslaMate.Log
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMateWeb.Api.Views.CarJSON

  action_fallback TeslaMateWeb.Api.FallbackController

  def index(conn, _params) do
    cars = Log.list_cars()
    json(conn, %{data: Enum.map(cars, &CarJSON.car/1)})
  end

  def show(conn, %{"id" => id}) do
    case Log.get_car(id) do
      nil -> {:error, :not_found}
      car -> json(conn, %{data: CarJSON.car_with_settings(car)})
    end
  end

  def summary(conn, %{"car_id" => car_id}) do
    car_id = String.to_integer(car_id)

    try do
      summary = Vehicle.summary(car_id)
      json(conn, %{data: CarJSON.summary(summary)})
    catch
      :exit, _ -> {:error, :not_found}
    end
  end
end
