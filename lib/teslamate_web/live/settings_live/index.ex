defmodule TeslaMateWeb.SettingsLive.Index do
  use Phoenix.LiveView

  import TeslaMateWeb.Gettext
  require Logger

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.SettingsView
  alias TeslaMate.Settings.{GlobalSettings, CarSettings}
  alias TeslaMate.Settings

  @impl true
  def render(assigns), do: SettingsView.render("index.html", assigns)

  @impl true
  def mount(_params, %{"settings" => settings, "locale" => locale}, socket) do
    if connected?(socket), do: Gettext.put_locale(locale)

    socket =
      socket
      |> assign_new(:addresses_migrated?, fn -> addresses_migrated?() end)
      |> assign_new(:car_settings, fn -> Settings.get_car_settings() |> prepare() end)
      |> assign_new(:car, fn -> nil end)
      |> assign(:global_settings, settings |> prepare())
      |> assign(:refreshing_addresses?, nil)
      |> assign(:refresh_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{car_settings: settings, car: car} = socket.assigns

    car =
      with id when not is_nil(id) <- Map.get(params, "car"),
           {id, ""} <- Integer.parse(id),
           true <- Map.has_key?(settings, id) do
        id
      else
        _ -> car || settings |> Map.keys() |> List.first()
      end

    {:noreply, assign(socket, car: car)}
  end

  @impl true
  def handle_event("car", %{"id" => id}, socket) do
    {:noreply, add_params(socket, car: id)}
  end

  def handle_event("change", %{"global_settings" => params}, %{assigns: assigns} = socket) do
    settings = fn ->
      case Settings.update_global_settings(assigns.global_settings.original, params) do
        {:error, %Ecto.Changeset{} = changeset} ->
          %{global_settings: Map.put(assigns.global_settings, :changeset, changeset)}

        {:error, reason} ->
          Logger.warn("Updating settings failed: #{inspect(reason, pretty: true)}")

          %{
            refresh_error:
              gettext(
                "There was a problem retrieving data from OpenStreetMap. Please try again later."
              )
          }

        {:ok, settings} ->
          %{global_settings: prepare(settings)}
      end
    end

    socket =
      if params["language"] != nil and params["language"] != assigns.global_settings.original do
        me = self()
        spawn_link(fn -> send(me, {:assigns, settings.()}) end)
        assign(socket, refreshing_addresses?: true)
      else
        assign(socket, settings.())
      end

    {:noreply, socket}
  end

  def handle_event("change", params, %{assigns: %{car_settings: settings, car: id}} = socket) do
    orig = get_in(settings, [id, :original])

    # workaround #1: switching between cars caused leex to not be re-evaluated.
    # Solution: custom ":as" attribute on form_for/4 for each CarSetting changeset
    params = params["car_settings_#{id}"]

    # workaround #2: enableding sleep mode caused previously disabled checkbox to be disabled
    params =
      if params["sleep_mode_enabled"] == "true" and not orig.sleep_mode_enabled do
        %{"sleep_mode_enabled" => "true"}
      else
        params
      end

    settings =
      orig
      |> Settings.update_car_settings(params)
      |> case do
        {:error, changeset} ->
          Logger.warn(inspect(changeset))
          put_in(settings, [id, :changeset], changeset)

        {:ok, car_settings} ->
          settings
          |> put_in([id, :original], car_settings)
          |> put_in([id, :changeset], Settings.change_car_settings(car_settings))
      end

    {:noreply, assign(socket, :car_settings, settings)}
  end

  @impl true
  def handle_info({:assigns, assigns}, socket) do
    socket =
      socket
      |> assign(refreshing_addresses?: false)
      |> assign(assigns)

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("Unexpected message: #{inspect(msg, pretty: true)}")
    {:noreply, socket}
  end

  # Private

  defp addresses_migrated? do
    alias TeslaMate.Log.{Drive, ChargingProcess}
    alias TeslaMate.Repo

    import Ecto.Query

    count_drives =
      from(d in Drive,
        select: count(),
        where:
          (is_nil(d.start_address_id) or is_nil(d.end_address_id)) and
            (not is_nil(d.start_position_id) and not is_nil(d.end_position_id))
      )

    count_charges =
      from(c in ChargingProcess,
        select: count(),
        where: is_nil(c.address_id) and not is_nil(c.position_id)
      )

    [d, c] =
      count_drives
      |> union_all(^count_charges)
      |> Repo.all()

    d + c == 0
  end

  defp add_params(socket, params) do
    push_redirect(socket, to: Routes.live_path(socket, __MODULE__, params), replace: true)
  end

  defp prepare(%GlobalSettings{} = settings) do
    %{original: settings, changeset: Settings.change_global_settings(settings)}
  end

  defp prepare(settings) do
    Enum.reduce(settings, %{}, fn %CarSettings{car: car} = s, acc ->
      Map.put(acc, car.id, %{original: s, changeset: Settings.change_car_settings(s)})
    end)
  end
end
