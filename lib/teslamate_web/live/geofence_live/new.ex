defmodule TeslaMateWeb.GeoFenceLive.New do
  use Phoenix.LiveView

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.GeoFenceLive
  alias TeslaMateWeb.GeoFenceView

  alias TeslaMate.{Locations, Settings, Convert}
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.Position
  alias TeslaMate.Log

  import TeslaMateWeb.Gettext

  @impl true
  def render(assigns), do: GeoFenceView.render("new.html", assigns)

  @impl true
  def mount(_session, socket) do
    {unit_of_length, radius} =
      case Settings.get_settings!() do
        %Settings.Settings{unit_of_length: :km} -> {:m, 20}
        %Settings.Settings{unit_of_length: :mi} -> {:ft, 65}
      end

    geo_fence = %GeoFence{radius: radius}

    assigns = %{
      geo_fence: geo_fence,
      changeset: Locations.change_geofence(geo_fence),
      unit_of_length: unit_of_length,
      show_errors: false
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_params(%{"lat" => lat, "lng" => lng}, _uri, socket) do
    changeset =
      socket.assigns.geo_fence
      |> Locations.change_geofence(%{latitude: lat, longitude: lng})

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_params(_params, _uri, socket) do
    attrs =
      case Log.get_latest_position() do
        %Position{latitude: lat, longitude: lng} -> %{latitude: lat, longitude: lng}
        nil -> %{}
      end

    changeset =
      socket.assigns.geo_fence
      |> Locations.change_geofence(attrs)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("validate", %{"geo_fence" => params}, socket) do
    changeset =
      %GeoFence{}
      |> Locations.change_geofence(params)
      |> Map.put(:action, :insert)

    {:noreply, assign(socket, changeset: changeset, show_errors: false)}
  end

  def handle_event("save", %{"geo_fence" => geofence_params}, socket) do
    geofence_params =
      Map.update(geofence_params, "radius", nil, fn radius ->
        case socket.assigns.unit_of_length do
          :ft -> with {radius, _} <- Float.parse(radius), do: Convert.ft_to_m(radius)
          :m -> radius
        end
      end)

    case Locations.create_geofence(geofence_params) do
      {:ok, %GeoFence{name: name}} ->
        {:stop,
         socket
         |> put_flash(:success, gettext("Geo-fence \"%{name}\" created", name: name))
         |> redirect(to: Routes.live_path(socket, GeoFenceLive.Index))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset, show_errors: true)}
    end
  end
end
