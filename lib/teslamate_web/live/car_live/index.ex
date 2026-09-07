defmodule TeslaMateWeb.CarLive.Index do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.{Log, Settings, Vehicles}
  alias TeslaMate.Settings.GlobalSettings

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    socket =
      socket
      |> assign(page_title: gettext("Home"))
      |> assign_new(:settings, fn -> update_base_url(settings, socket) end)
      |> assign_vehicles(Vehicles.list())
      |> assign(reloading?: false, reload_error: nil)

    {:ok, socket}
  end

  # Reloading restarts the vehicle supervisor, which makes exactly one
  # (billed) call to the Tesla API. It is only offered while no vehicle is
  # logged, so no running logger gets interrupted.
  @impl true
  def handle_event("reload_vehicles", _params, %{assigns: %{reloading?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("reload_vehicles", _params, socket) do
    # A stale tab may still show the button after another tab or a sign-in
    # started the loggers. Then the page catches up instead of restarting them.
    case Vehicles.list() do
      [] -> {:noreply, start_reload(socket)}
      summaries -> {:noreply, assign_vehicles(socket, summaries)}
    end
  end

  @impl true
  def handle_async(:reload_vehicles, {:ok, {:ok, summaries}}, socket) do
    socket = socket |> assign(reloading?: false) |> assign_vehicles(summaries)

    case socket.assigns.discovery do
      {:error, :not_signed_in} ->
        {:noreply, redirect(socket, to: Routes.live_path(socket, TeslaMateWeb.SignInLive.Index))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:reload_vehicles, {:ok, {:error, reason}}, socket) do
    {:noreply, reload_failed(socket, reason)}
  end

  def handle_async(:reload_vehicles, {:exit, reason}, socket) do
    {:noreply, reload_failed(socket, reason)}
  end

  ## Private

  defp start_reload(socket) do
    socket
    |> assign(reloading?: true, reload_error: nil)
    |> start_async(:reload_vehicles, fn ->
      with :ok <- Vehicles.restart() do
        {:ok, Vehicles.list()}
      end
    end)
  end

  # With an empty list, the reason for the emptiness is what the page has to
  # explain. Cars known from the database are logged unless data collection
  # is disabled for them, so known cars plus an empty list means every car is
  # disabled, whatever the Tesla API answered.
  defp assign_vehicles(socket, summaries) do
    assign(socket,
      summaries: summaries,
      discovery: Vehicles.discovery_result(),
      known_cars?: summaries == [] and Log.list_cars() != []
    )
  end

  defp reload_failed(socket, reason) do
    Logger.warning("Reloading vehicles failed: #{inspect(reason)}")

    assign(socket,
      reloading?: false,
      reload_error: gettext("Reloading the vehicles failed. Please check the logs.")
    )
  end

  defp discovery_hint({:error, :no_vehicles}) do
    gettext(
      "Your Tesla account does not contain a vehicle yet. Once the vehicle shows up in the Tesla app, reload the vehicle list."
    )
  end

  defp discovery_hint({:error, :too_many_request}) do
    gettext(
      "The Tesla API rate limit was exceeded while fetching the vehicles. Please wait a few minutes before reloading."
    )
  end

  defp discovery_hint({:error, reason}) do
    gettext("Fetching the vehicles from the Tesla API failed: %{reason}", reason: inspect(reason))
  end

  defp update_base_url(%GlobalSettings{base_url: url} = settings, socket)
       when is_nil(url) or url == "" do
    if connected?(socket) do
      base_url = get_connect_params(socket)["baseUrl"]

      case Settings.update_global_settings(settings, %{base_url: base_url}) do
        {:error, reason} ->
          Logger.warning("Updating settings failed: #{inspect(reason)}")
          settings

        {:ok, settings} ->
          settings
      end
    else
      settings
    end
  end

  defp update_base_url(settings, _socket) do
    settings
  end
end
