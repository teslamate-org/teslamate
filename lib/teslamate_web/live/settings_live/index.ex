defmodule TeslaMateWeb.SettingsLive.Index do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.Settings.{GlobalSettings, CarSettings}
  alias TeslaMate.{Settings, Updater, Api}

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    assigns = %{
      addresses_migrated?: addresses_migrated?(),
      car_settings: Settings.get_car_settings() |> prepare(),
      car: nil,
      global_settings: settings |> prepare(),
      update: Updater.get_update(),
      refreshing_addresses?: nil,
      refresh_error: nil,
      page_title: gettext("Settings")
    }

    {:ok, assign(socket, assigns)}
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

  def handle_event("change", %{"global_settings" => %{"ui" => ui}}, %{assigns: %{locale: lo}} = s)
      when ui != lo do
    {:noreply, redirect(s, to: Routes.live_path(s, __MODULE__, locale: ui))}
  end

  def handle_event("change", %{"global_settings" => params}, %{assigns: assigns} = socket) do
    settings = fn ->
      case Settings.update_global_settings(assigns.global_settings.original, params) do
        {:error, %Ecto.Changeset{} = changeset} ->
          %{global_settings: Map.put(assigns.global_settings, :changeset, changeset)}

        {:error, reason} ->
          Logger.warning("Updating settings failed: #{inspect(reason, pretty: true)}")

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
    params = params["car_settings_#{id}"]

    settings =
      get_in(settings, [id, :original])
      |> Settings.update_car_settings(params)
      |> case do
        {:error, changeset} ->
          Logger.warning(inspect(changeset))
          put_in(settings, [id, :changeset], changeset)

        {:ok, car_settings} ->
          settings
          |> put_in([id, :original], car_settings)
          |> put_in([id, :changeset], Settings.change_car_settings(car_settings))
      end

    {:noreply, assign(socket, :car_settings, settings)}
  end

  def handle_event("sign_out", _params, socket) do
    :ok = Api.sign_out()
    {:noreply, redirect(socket, to: Routes.car_path(socket, :index))}
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

  @language_tags (GlobalSettings.supported_languages() ++
                    [
                      {"Norwegian", "nb"},
                      {"Chinese (simplified)", "zh_Hans"},
                      {"Chinese (traditional)", "zh_Hant"}
                    ])
                 |> Enum.map(fn {key, val} -> {val, key} end)
                 |> Enum.into(%{})

  @supported_ui_languages TeslaMateWeb.Cldr.known_locale_names()
                          |> Enum.reject(&(&1 in [:zh]))
                          |> Enum.map(&String.replace(to_string(&1), "-", "_"))
                          |> Enum.map(&{Map.get(@language_tags, &1, &1), &1})
                          |> Enum.sort_by(&elem(&1, 0))

  defp supported_ui_languages, do: @supported_ui_languages

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
