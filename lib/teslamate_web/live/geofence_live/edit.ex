defmodule TeslaMateWeb.GeoFenceLive.Edit do
  use Phoenix.LiveView

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.GeoFenceLive
  alias TeslaMateWeb.GeoFenceView

  alias TeslaMate.Addresses.GeoFence
  alias TeslaMate.Addresses

  import TeslaMateWeb.Gettext

  def render(assigns), do: GeoFenceView.render("edit.html", assigns)

  def mount(%{path_params: %{"id" => id}}, socket) do
    geofence = Addresses.get_geofence!(id)

    assigns = %{
      geofence: geofence,
      changeset: Addresses.change_geofence(geofence),
      type: :edit,
      show_errors: false
    }

    {:ok, assign(socket, assigns)}
  end

  def handle_event("validate", %{"geo_fence" => params}, socket) do
    changeset =
      socket.assigns.geofence
      |> Addresses.change_geofence(params)
      |> Map.put(:action, :update)

    {:noreply, assign(socket, changeset: changeset, show_errors: false)}
  end

  def handle_event("save", %{"geo_fence" => geofence_params}, socket) do
    case Addresses.update_geofence(socket.assigns.geofence, geofence_params) do
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
