defmodule TeslaMateWeb.CarController do
  use TeslaMateWeb, :controller

  require Logger

  alias TeslaMate.{Log, Vehicles}

  action_fallback TeslaMateWeb.FallbackController

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
