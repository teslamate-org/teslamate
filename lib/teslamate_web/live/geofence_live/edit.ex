defmodule TeslaMateWeb.GeoFenceLive.Edit do
  use Phoenix.LiveView

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.GeoFenceLive
  alias TeslaMateWeb.GeoFenceView

  alias TeslaMate.{Locations, Settings, Convert}
  alias TeslaMate.Locations.GeoFence

  import TeslaMateWeb.Gettext

  @impl true
  def render(assigns), do: GeoFenceView.render("edit.html", assigns)

  @impl true
  def mount(_session, socket) do
    {:ok, assign(socket, show_errors: false)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    %GeoFence{radius: radius} = geofence = Locations.get_geofence!(id)

    {unit_of_length, radius} =
      case Settings.get_settings!() do
        %Settings.Settings{unit_of_length: :km} -> {:m, radius}
        %Settings.Settings{unit_of_length: :mi} -> {:ft, Convert.m_to_ft(radius)}
      end

    assigns = %{
      geofence: geofence,
      changeset: Locations.change_geofence(geofence, %{radius: round(radius)}),
      unit_of_length: unit_of_length
    }

    {:noreply, assign(socket, assigns)}
  end

  @impl true
  def handle_event("validate", %{"geo_fence" => params}, socket) do
    changeset =
      socket.assigns.geofence
      |> Locations.change_geofence(params)
      |> Map.put(:action, :update)

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

    case Locations.update_geofence(socket.assigns.geofence, geofence_params) do
      {:ok, %GeoFence{name: name}} ->
        {:stop,
         socket
         |> put_flash(:success, gettext("Geo-fence \"%{name}\" updated successfully", name: name))
         |> redirect(to: Routes.live_path(socket, GeoFenceLive.Index))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset, show_errors: true)}
    end
  end
end
