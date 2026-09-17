defmodule TeslaMateWeb.CarLive.Index do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.{Log, Settings, Vehicles}
  alias TeslaMate.Settings.GlobalSettings

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    if connected?(socket), do: :ok = Vehicles.subscribe()

    socket =
      socket
      |> assign(page_title: gettext("Home"))
      |> assign_new(:settings, fn -> update_base_url(settings, socket) end)
      |> assign(reloading?: false, reload_error: nil)
      |> assign_vehicles()

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
      _summaries -> {:noreply, refresh(socket)}
    end
  end

  @impl true
  def handle_async(:reload_vehicles, {:ok, :ok}, socket) do
    {:noreply, socket |> assign(reloading?: false) |> refresh()}
  end

  # Another restart is running; its result arrives as a reload message.
  def handle_async(:reload_vehicles, {:ok, {:error, :restarting}}, socket) do
    {:noreply, socket |> assign(reloading?: false) |> refresh()}
  end

  def handle_async(:reload_vehicles, {:ok, {:error, reason}}, socket) do
    {:noreply, reload_failed(socket, reason)}
  end

  def handle_async(:reload_vehicles, {:exit, reason}, socket) do
    {:noreply, reload_failed(socket, reason)}
  end

  @impl true
  def handle_info({Vehicles, :reloaded}, socket) do
    {:noreply, refresh(socket)}
  end

  ## Private

  defp start_reload(socket) do
    socket
    |> assign(reloading?: true, reload_error: nil)
    |> start_async(:reload_vehicles, fn -> Vehicles.restart(wait: false) end)
  end

  defp refresh(socket) do
    socket = assign_vehicles(socket)

    case socket.assigns.status do
      {:error, :not_signed_in} ->
        redirect(socket, to: Routes.live_path(socket, TeslaMateWeb.SignInLive.Index))

      _ ->
        socket
    end
  end

  # With an empty list, the reason for the emptiness is what the page has to
  # explain. While the loggers run, cars known from the database are logged
  # unless data collection is disabled for them, so known cars plus an empty
  # list means every car is disabled, whatever the Tesla API answered.
  #
  # The status is read before the list: a restart starting in between then
  # shows as a stale non-empty list, never as a false "all disabled".
  defp assign_vehicles(socket) do
    status = Vehicles.status()
    summaries = Vehicles.list()

    assign(socket,
      status: status,
      summaries: summaries,
      known_cars?: summaries == [] and running?(status) and Log.list_cars() != []
    )
  end

  defp running?(:restarting), do: false
  defp running?({:error, {:start_failed, _reason}}), do: false
  defp running?(_status), do: true

  defp reload_failed(socket, reason) do
    Logger.warning("Reloading vehicles failed: #{inspect(reason)}")

    assign(socket,
      reloading?: false,
      reload_error: gettext("Reloading the vehicles failed. Please check the logs.")
    )
  end

  defp status_hint(:restarting) do
    gettext("The vehicle list is being reloaded right now. This page updates once it is done.")
  end

  defp status_hint({:error, {:start_failed, reason}}) do
    gettext("Starting the vehicle loggers failed: %{reason}. Please check the logs.",
      reason: inspect(reason)
    )
  end

  defp status_hint({:error, :no_vehicles}) do
    gettext(
      "Your Tesla account does not contain a vehicle yet. Once the vehicle shows up in the Tesla app, reload the vehicle list."
    )
  end

  defp status_hint({:error, :too_many_request}) do
    gettext(
      "The Tesla API rate limit was exceeded while fetching the vehicles. Please wait a few minutes before reloading."
    )
  end

  defp status_hint({:error, reason}) do
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
