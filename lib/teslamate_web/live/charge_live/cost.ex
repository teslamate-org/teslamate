defmodule TeslaMateWeb.ChargeLive.Cost do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.Locations.{GeoFence, Address}
  alias TeslaMate.Log.ChargingProcess
  alias TeslaMate.Log

  import TeslaMateWeb.Gettext

  @impl true
  def mount(%{"id" => id}, %{"locale" => locale}, socket) do
    if connected?(socket), do: Gettext.put_locale(locale)

    charging_process = Log.get_charging_process!(id)

    socket =
      socket
      |> assign(notification: nil, page_title: gettext("Charge Cost"))
      |> assign_charging_process(charging_process)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    referrer =
      case {get_connect_params(socket)["referrer"], uri} do
        {uri, uri} -> nil
        {"", _uri} -> nil
        {referrer, _} when is_binary(referrer) -> referrer
        _ -> nil
      end

    {:noreply, assign(socket, redirect_to: referrer || Routes.car_path(socket, :index))}
  end

  @impl true
  def handle_event("save", %{"charging_process" => params}, socket) do
    params =
      case params do
        %{"cost" => cost, "mode" => "per_kwh"} when is_binary(cost) ->
          kwh =
            socket.assigns.charging_process
            |> Map.take([:charge_energy_added, :charge_energy_used])
            |> Map.values()
            |> Enum.reject(&is_nil/1)
            |> case do
              [k0, k1] -> Decimal.max(k0, k1)
              [kwh] -> kwh
              [] -> nil
            end

          with true <- match?(%Decimal{}, kwh),
               {cost_per_kwh, ""} <- Float.parse(cost) do
            cost =
              cost_per_kwh
              |> Decimal.from_float()
              |> Decimal.mult(kwh)

            Map.put(params, "cost", cost)
          else
            _ -> params
          end

        %{"cost" => cost, "mode" => "per_minute"} when is_binary(cost) ->
          with %ChargingProcess{duration_min: minutes} when is_number(minutes) <-
                 socket.assigns.charging_process,
               {cost_per_minute, ""} <- Float.parse(cost) do
            cost =
              cost_per_minute
              |> Decimal.from_float()
              |> Decimal.mult(minutes)

            Map.put(params, "cost", cost)
          else
            _ -> params
          end

        %{"cost" => _} ->
          params
      end

    case Log.update_charging_process(socket.assigns.charging_process, params) do
      {:ok, charging_process} ->
        notification = create_notification(:success, gettext("Saved!"))

        socket =
          socket
          |> assign(notification: notification)
          |> assign_charging_process(charging_process)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_info({:remove_notification, id}, %{assigns: %{notification: %{id: id}}} = socket) do
    socket =
      socket
      |> assign(notification: nil)
      |> assign_charging_process(socket.assigns.charging_process, nil)

    {:noreply, socket}
  end

  def handle_info({:remove_notification, _id}, socket) do
    {:noreply, socket}
  end

  # Private

  defp assign_charging_process(socket, %ChargingProcess{} = c, mode \\ "total") do
    assign(socket, charging_process: c, changeset: ChargingProcess.changeset(c, %{mode: mode}))
  end

  defp create_notification(key, msg) do
    id = make_ref()
    Process.send_after(self(), {:remove_notification, id}, 2500)
    %{id: id, message: msg, key: key}
  end
end
