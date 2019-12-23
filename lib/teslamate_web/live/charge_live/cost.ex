defmodule TeslaMateWeb.ChargeLive.Cost do
  use Phoenix.LiveView

  require Logger

  alias TeslaMateWeb.ChargeView
  alias TeslaMateWeb.Router.Helpers, as: Routes

  alias TeslaMate.Log.ChargingProcess
  alias TeslaMate.Log

  @impl true
  def render(assigns), do: ChargeView.render("cost.html", assigns)

  @impl true
  def mount(_session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, uri, socket) do
    charging_process = Log.get_charging_process!(id)

    referrer =
      case {get_connect_params(socket)["referrer"], uri} do
        {uri, uri} -> nil
        {"", _uri} -> nil
        {referrer, _} when is_binary(referrer) -> referrer
        _ -> nil
      end

    assigns = %{
      charging_process: charging_process,
      changeset: ChargingProcess.changeset(charging_process, %{}),
      redirect_to: referrer || Routes.car_path(socket, :index)
    }

    {:noreply, assign(socket, assigns)}
  end

  @impl true
  def handle_event("save", %{"charging_process" => params}, socket) do
    case Log.update_charging_process(socket.assigns.charging_process, params) do
      {:ok, _charging_process} ->
        {:stop, redirect(socket, to: socket.assigns.redirect_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
