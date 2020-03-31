defmodule TeslaMateWeb.GeoFenceLive.Form do
  use Phoenix.LiveView

  require Logger

  alias TeslaMateWeb.{GeoFenceLive, GeoFenceView}
  alias TeslaMateWeb.Router.Helpers, as: Routes

  alias TeslaMate.{Log, Locations, Settings}
  alias TeslaMate.Settings.{GlobalSettings, CarSettings}
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.{Car, Position}

  import TeslaMateWeb.Gettext

  @impl true
  def render(assigns), do: GeoFenceView.render("form.html", assigns)

  @impl true
  def mount(%{"id" => id}, session, socket) do
    %{"settings" => settings, "locale" => locale} = session

    if connected?(socket) do
      Gettext.put_locale(locale)
    end

    geofence = Locations.get_geofence!(id)

    {:ok, base_assigns(socket, geofence, settings, :edit)}
  end

  def mount(%{"lat" => lat, "lng" => lng}, session, socket) do
    %{"settings" => settings, "locale" => locale} = session

    if connected?(socket) do
      Gettext.put_locale(locale)
    end

    {:ok, settings} = set_grafana_url(settings, socket)

    geofence = %GeoFence{
      radius: 20,
      latitude: lat,
      longitude: lng,
      sleep_mode_blacklist: [],
      sleep_mode_whitelist: []
    }

    {:ok, base_assigns(socket, geofence, settings, :new)}
  end

  def mount(_params, session, socket) do
    %{"settings" => settings, "locale" => locale} = session

    if connected?(socket) do
      Gettext.put_locale(locale)
    end

    %{latitude: lat, longitude: lng} =
      case Log.get_latest_position() do
        %Position{latitude: lat, longitude: lng} -> %{latitude: lat, longitude: lng}
        nil -> %{latitude: 0.0, longitude: 0.0}
      end

    geofence = %GeoFence{
      radius: 20,
      latitude: lat,
      longitude: lng,
      sleep_mode_blacklist: [],
      sleep_mode_whitelist: []
    }

    {:ok, base_assigns(socket, geofence, settings, :new)}
  end

  @impl true
  def handle_event("validate", %{"geo_fence" => params}, socket) do
    changeset =
      socket.assigns.geofence
      |> Locations.change_geofence(params)
      |> Map.put(:action, :update)

    {:noreply, assign(socket, changeset: changeset, show_errors: false)}
  end

  def handle_event("toggle", %{"checked" => value, "car" => id}, socket) do
    %{
      car_settings: car_settings,
      sleep_mode_blacklist: blacklist,
      sleep_mode_whitelist: whitelist
    } = socket.assigns

    car_id = String.to_integer(id)

    %CarSettings{sleep_mode_enabled: sleep_mode_enabled, car: car} =
      Enum.find(car_settings, fn s -> s.car.id == car_id end)

    assigns =
      if sleep_mode_enabled do
        blacklist =
          case value do
            "false" -> Enum.uniq([car | blacklist])
            "true" -> Enum.reject(blacklist, &match?(%Car{id: ^car_id}, &1))
          end

        %{sleep_mode_blacklist: blacklist}
      else
        whitelist =
          case value do
            "false" -> Enum.reject(whitelist, &match?(%Car{id: ^car_id}, &1))
            "true" -> Enum.uniq([car | whitelist])
          end

        %{sleep_mode_whitelist: whitelist}
      end

    {:noreply, assign(socket, assigns)}
  end

  def handle_event("save", %{"geo_fence" => params}, socket) do
    with {:ok, geofence, changeset} <- validate(params, socket),
         {:ok, socket} <- show_modal_or_save(geofence, changeset, socket) do
      {:noreply, socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset, show_errors: true)}
    end
  end

  def handle_event("calc-costs", %{"result" => result}, socket) do
    case save(socket) do
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset, show_modal: false, show_errors: true)}

      {:ok, socket} ->
        if result == "yes" do
          :ok = Locations.calculate_charge_costs(socket.assigns.geofence)
        end

        {:noreply, socket}
    end
  end

  def handle_event("close-modal", _, socket) do
    {:noreply, assign(socket, show_modal: false)}
  end

  def handle_event("keyup", %{"code" => "Escape"}, socket) do
    {:noreply, assign(socket, show_modal: false)}
  end

  def handle_event("keyup", _, socket) do
    {:noreply, socket}
  end

  # Private

  defp base_assigns(socket, %GeoFence{} = geofence, %GlobalSettings{} = settings, action)
       when action in [:new, :edit] do
    assigns = %{
      settings: settings,
      geofence: geofence,
      changeset: Locations.change_geofence(geofence),
      car_settings: Settings.get_car_settings(),
      sleep_mode_whitelist: geofence.sleep_mode_whitelist,
      sleep_mode_blacklist: geofence.sleep_mode_blacklist,
      charges_without_costs: 0,
      show_errors: false,
      show_modal: false,
      action: action,
      connected?: connected?(socket)
    }

    assign(socket, assigns)
  end

  defp validate(params, %{assigns: assigns}) do
    changeset = Locations.change_geofence(assigns.geofence, params)

    with {:ok, geofence} <- Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, geofence, changeset}
    end
  end

  defp show_modal_or_save(%GeoFence{} = geofence, changeset, socket) do
    has_cost = geofence.session_fee != nil or geofence.cost_per_kwh != nil

    position_or_cost_changed =
      has_changed?(changeset, [:cost_per_kwh, :session_fee, :latitude, :longitude, :radius])

    with true <- has_cost and position_or_cost_changed,
         n when n > 0 <- Locations.count_charging_processes_without_costs(geofence) do
      socket =
        assign(socket,
          show_modal: true,
          changeset: changeset,
          charges_without_costs: n
        )

      {:ok, socket}
    else
      _ -> socket |> assign(changeset: changeset) |> save()
    end
  end

  defp save(%{assigns: assigns} = socket) do
    params =
      assigns.changeset.params
      |> Map.put("sleep_mode_blacklist", assigns.sleep_mode_blacklist)
      |> Map.put("sleep_mode_whitelist", assigns.sleep_mode_whitelist)

    with {:ok, %GeoFence{name: name} = geofence} <-
           (case assigns.action do
              :new -> Locations.create_geofence(params)
              :edit -> Locations.update_geofence(assigns.geofence, params)
            end) do
      socket =
        socket
        |> assign(geofence: geofence)
        |> put_flash(:success, flash_msg(assigns.action, name))
        |> redirect(to: Routes.live_path(socket, GeoFenceLive.Index))

      {:ok, socket}
    end
  end

  defp set_grafana_url(settings, socket) do
    with nil <- settings.grafana_url,
         %{"referrer" => referrer} when is_binary(referrer) <- get_connect_params(socket),
         %URI{path: path} = url when is_binary(path) <- URI.parse(referrer),
         [_, _, _ | path] <- path |> String.split("/") |> Enum.reverse(),
         url = %URI{url | path: Enum.join([nil | path], "/"), query: nil} |> URI.to_string(),
         {:ok, settings} <- Settings.update_global_settings(settings, %{grafana_url: url}) do
      {:ok, settings}
    else
      {:error, reason} -> Logger.warn("Updating settings failed: #{inspect(reason)}")
      _ -> {:ok, settings}
    end
  end

  defp has_changed?(%Ecto.Changeset{changes: changes}, keys) do
    length(keys -- Map.keys(changes)) < length(keys)
  end

  defp flash_msg(:new, name), do: gettext("Geo-fence \"%{name}\" created", name: name)
  defp flash_msg(:edit, name), do: gettext("Geo-fence \"%{name}\" updated", name: name)
end
