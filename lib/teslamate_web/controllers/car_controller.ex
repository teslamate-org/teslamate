defmodule TeslaMateWeb.CarController do
  use TeslaMateWeb, :controller

  require Logger
  import Phoenix.LiveView.Controller

  alias TeslaMate.Api, warn: false
  alias TeslaMate.{Log, Vehicles}

  plug :redirect_if_importing when action in [:index]
  plug :fetch_signed_in when action in [:index]
  plug :redirect_unless_signed_in when action in [:index]

  action_fallback TeslaMateWeb.FallbackController

  def index(conn, _) do
    live_render(conn, TeslaMateWeb.CarLive.Index,
      session: %{
        "settings" => conn.assigns[:settings],
        "locale" => get_session(conn, :locale)
      }
    )
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
    :ok = Vehicles.resume_logging(car.id)
    send_resp(conn, :no_content, "")
  end

  case Mix.env() do
    :test -> defp fetch_signed_in(conn, _opts), do: conn
    _ -> defp fetch_signed_in(conn, _opts), do: assign(conn, :signed_in?, Api.signed_in?())
  end

  defp redirect_if_importing(conn, _) do
    case Application.get_env(:teslamate, :import_directory) do
      nil -> conn
      _ -> conn |> redirect(to: import_page(conn)) |> halt()
    end
  end

  defp redirect_unless_signed_in(%Plug.Conn{assigns: %{signed_in?: true}} = conn, _), do: conn
  defp redirect_unless_signed_in(conn, _opts), do: conn |> redirect(to: sign_in(conn)) |> halt()

  defp sign_in(conn), do: Routes.live_path(conn, TeslaMateWeb.SignInLive.Index)
  defp import_page(conn), do: Routes.live_path(conn, TeslaMateWeb.ImportLive.Index)
end
