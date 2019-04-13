defmodule TeslaMateWeb.CarController do
  use TeslaMateWeb, :controller

  require Logger

  alias TeslaMate.Log
  alias TeslaMate.Log.Car
  alias TeslaMate.Vehicles

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

  def suspend_logging(conn, %{"id" => id}) do
    car = Log.get_car!(id)

    case Vehicles.suspend_logging(car.id) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        Logger.info("Could not suspend manually: #{inspect(reason)}")

        conn
        |> put_status(:precondition_failed)
        |> render("command_failed.json", reason: reason)
    end
  end

  def resume_logging(conn, %{"id" => id}) do
    car = Log.get_car!(id)

    case Vehicles.resume_logging(car.id) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        Logger.info("Could not resume manually: #{inspect(reason)}")

        conn
        |> put_status(:bad_gateway)
        |> render("command_failed.json", reason: reason)
    end
  end
end
