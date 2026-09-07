defmodule TeslaMateWeb.CarLive.Index do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.{Settings, Vehicles}
  alias TeslaMate.Settings.GlobalSettings

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    socket =
      socket
      |> assign(page_title: gettext("Home"))
      |> assign_new(:summaries, fn -> Vehicles.list() end)
      |> assign_new(:settings, fn -> update_base_url(settings, socket) end)
      |> assign(discovery: Vehicles.discovery_result(), reloading?: false, reload_error: nil)

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
    socket =
      socket
      |> assign(reloading?: true, reload_error: nil)
      |> start_async(:reload_vehicles, fn ->
        with :ok <- Vehicles.restart() do
          {:ok, Vehicles.list(), Vehicles.discovery_result()}
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:reload_vehicles, {:ok, {:ok, _summaries, {:error, :not_signed_in}}}, socket) do
    {:noreply, redirect(socket, to: Routes.live_path(socket, TeslaMateWeb.SignInLive.Index))}
  end

  def handle_async(:reload_vehicles, {:ok, {:ok, summaries, discovery}}, socket) do
    {:noreply, assign(socket, reloading?: false, summaries: summaries, discovery: discovery)}
  end

  def handle_async(:reload_vehicles, {:ok, {:error, reason}}, socket) do
    {:noreply, reload_failed(socket, reason)}
  end

  def handle_async(:reload_vehicles, {:exit, reason}, socket) do
    {:noreply, reload_failed(socket, reason)}
  end

  ## Private

  defp reload_failed(socket, reason) do
    Logger.warning("Reloading vehicles failed: #{inspect(reason)}")

    assign(socket,
      reloading?: false,
      reload_error: gettext("Reloading the vehicles failed. Please check the logs.")
    )
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
