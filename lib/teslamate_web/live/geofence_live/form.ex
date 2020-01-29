defmodule TeslaMateWeb.GeoFenceLive.Form do
  use Phoenix.LiveView

  require Logger

  alias TeslaMateWeb.{GeoFenceLive, GeoFenceView}
  alias TeslaMateWeb.Router.Helpers, as: Routes

  alias TeslaMate.{Log, Locations, Settings, Convert}
  alias TeslaMate.Settings.{GlobalSettings, CarSettings}
  alias TeslaMate.Log.{Car, Position}
  alias TeslaMate.Locations.GeoFence

  import TeslaMateWeb.Gettext

  @impl true
  def render(assigns), do: GeoFenceView.render("form.html", assigns)

  @impl true
  def mount(%{"id" => id}, session, socket) do
    %{"settings" => settings, "locale" => locale} = session

    if connected?(socket) do
      Gettext.put_locale(locale)
    end

    geofence = %GeoFence{radius: radius} = Locations.get_geofence!(id)

    {unit_of_length, radius} =
      case settings do
        %GlobalSettings{unit_of_length: :km} -> {:m, radius}
        %GlobalSettings{unit_of_length: :mi} -> {:ft, Convert.m_to_ft(radius)}
      end

    assigns =
      base_assigns(geofence, %{radius: round(radius)})
      |> Map.merge(%{action: :edit, settings: settings, unit_of_length: unit_of_length})

    {:ok, assign(socket, assigns)}
  end

  def mount(%{"lat" => lat, "lng" => lng}, session, socket) do
    %{"settings" => settings, "locale" => locale} = session

    if connected?(socket) do
      Gettext.put_locale(locale)
    end

    {:ok, settings} = set_grafana_url(settings, socket)

    {unit_of_length, radius} =
      case settings do
        %GlobalSettings{unit_of_length: :km} -> {:m, 20}
        %GlobalSettings{unit_of_length: :mi} -> {:ft, 65}
      end

    geofence = %GeoFence{
      radius: radius,
      latitude: lat,
      longitude: lng,
      sleep_mode_blacklist: [],
      sleep_mode_whitelist: []
    }

    assigns =
      base_assigns(geofence)
      |> Map.merge(%{action: :new, settings: settings, unit_of_length: unit_of_length})

    {:ok, assign(socket, assigns)}
  end

  def mount(_params, session, socket) do
    %{"settings" => settings, "locale" => locale} = session

    if connected?(socket) do
      Gettext.put_locale(locale)
    end

    {unit_of_length, radius} =
      case settings do
        %GlobalSettings{unit_of_length: :km} -> {:m, 20}
        %GlobalSettings{unit_of_length: :mi} -> {:ft, 65}
      end

    %{latitude: lat, longitude: lng} =
      case Log.get_latest_position() do
        %Position{latitude: lat, longitude: lng} -> %{latitude: lat, longitude: lng}
        nil -> %{latitude: 0.0, longitude: 0.0}
      end

    geofence = %GeoFence{
      radius: radius,
      latitude: lat,
      longitude: lng,
      sleep_mode_blacklist: [],
      sleep_mode_whitelist: []
    }

    assigns =
      base_assigns(geofence)
      |> Map.merge(%{action: :new, settings: settings, unit_of_length: unit_of_length})

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("move", %{"lat" => lat, "lng" => lng}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.change(%{latitude: lat, longitude: lng})

    {:noreply, assign(socket, changeset: changeset, show_errors: false)}
  end

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
    geofence_params =
      params
      |> Map.update("radius", nil, fn radius ->
        case socket.assigns.unit_of_length do
          :ft -> with {radius, _} <- Float.parse(radius), do: Convert.ft_to_m(radius)
          :m -> radius
        end
      end)
      |> Map.put("sleep_mode_blacklist", socket.assigns.sleep_mode_blacklist)
      |> Map.put("sleep_mode_whitelist", socket.assigns.sleep_mode_whitelist)

    case socket.assigns.action do
      :new -> Locations.create_geofence(geofence_params)
      :edit -> Locations.update_geofence(socket.assigns.geofence, geofence_params)
    end
    |> case do
      {:ok, %GeoFence{name: name}} ->
        {:stop,
         socket
         |> put_flash(:success, flash_msg(socket.assigns.action, name))
         |> redirect(to: Routes.live_path(socket, GeoFenceLive.Index))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset, show_errors: true)}
    end
  end

  # Private

  defp base_assigns(geofence, attrs \\ %{}) do
    %{
      geofence: geofence,
      changeset: Locations.change_geofence(geofence, attrs),
      car_settings: Settings.get_car_settings(),
      sleep_mode_whitelist: geofence.sleep_mode_whitelist,
      sleep_mode_blacklist: geofence.sleep_mode_blacklist,
      show_errors: false
    }
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

  defp flash_msg(:new, name), do: gettext("Geo-fence \"%{name}\" created", name: name)
  defp flash_msg(:edit, name), do: gettext("Geo-fence \"%{name}\" updated", name: name)
end
