defmodule TeslaMateWeb.CarController do
  use TeslaMateWeb, :controller

  alias TeslaMate.Log
  alias TeslaMate.Log.Car

  action_fallback TeslaMateWeb.FallbackController

  def index(conn, _params) do
    car = Log.list_cars()
    render(conn, "index.json", car: car)
  end

  def show(conn, %{"id" => id}) do
    car = Log.get_car!(id)
    render(conn, "show.json", car: car)
  end

  def update(conn, %{"id" => id, "car" => car_params}) do
    car = Log.get_car!(id)

    with {:ok, %Car{} = car} <- Log.update_car(car, car_params) do
      render(conn, "show.json", car: car)
    end
  end
end
