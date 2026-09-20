defmodule TeslaMateWeb.CarLive.Index do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.{Log, Settings, Vehicles}
  alias TeslaMate.Settings.GlobalSettings
  alias TeslaMateWeb.VehicleReload

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    if connected?(socket), do: :ok = Vehicles.subscribe()

    socket =
      socket
      |> assign(page_title: gettext("Home"))
      |> assign_new(:settings, fn -> update_base_url(settings, socket) end)
      |> assign(reloading?: false, reload_error: nil, reload: nil)
      |> assign_vehicles()

    {:ok, socket}
  end

  # One (billed) call to the Tesla API per click, see Vehicles.discover/0.
  @impl true
  def handle_event("reload_vehicles", _params, %{assigns: %{reloading?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("reload_vehicles", _params, socket) do
    socket =
      socket
      |> assign(reloading?: true, reload_error: nil)
      |> start_async(:reload_vehicles, fn -> Vehicles.discover() end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:reload_vehicles, {:ok, {:error, :not_signed_in}}, socket) do
    {:noreply, redirect(socket, to: Routes.live_path(socket, TeslaMateWeb.SignInLive.Index))}
  end

  def handle_async(:reload_vehicles, {:ok, result}, socket) do
    socket = socket |> assign(reloading?: false, reload: result) |> assign_vehicles()
    {:noreply, socket}
  end

  def handle_async(:reload_vehicles, {:exit, reason}, socket) do
    Logger.warning("Reloading vehicles failed: #{inspect(reason)}")

    socket = assign(socket, reloading?: false, reload_error: VehicleReload.crashed())

    {:noreply, socket}
  end

  @impl true
  def handle_info({Vehicles, :vehicles_changed}, socket) do
    {:noreply, assign_vehicles(socket)}
  end

  ## Private

  # A car known from the database has no logger exactly when its data
  # collection is disabled or it was not in the account's vehicle list when
  # the loggers started. Whether that start-up list was empty or the request
  # failed is not recorded; only the result of a reload is.
  defp assign_vehicles(socket) do
    summaries = Vehicles.list()
    assign(socket, summaries: summaries, known_cars?: summaries == [] and Log.list_cars() != [])
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
