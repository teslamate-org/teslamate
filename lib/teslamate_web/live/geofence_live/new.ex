defmodule TeslaMateWeb.GeoFenceLive.New do
  use Phoenix.LiveView

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.GeoFenceLive
  alias TeslaMateWeb.GeoFenceView

  alias TeslaMate.Addresses.GeoFence
  alias TeslaMate.Addresses

  import TeslaMateWeb.Gettext

  def render(assigns), do: GeoFenceView.render("new.html", assigns)

  def mount(_session, socket) do
    assigns = %{
      changeset: Addresses.change_geofence(%GeoFence{}, %{radius: 20}),
      type: :create,
      show_errors: false
    }

    {:ok, assign(socket, assigns)}
  end

  def handle_event("validate", %{"geo_fence" => params}, socket) do
    changeset =
      %GeoFence{}
      |> Addresses.change_geofence(params)
      |> Map.put(:action, :insert)

    {:noreply, assign(socket, changeset: changeset, show_errors: false)}
  end

  def handle_event("save", %{"geo_fence" => geofence_params}, socket) do
    case Addresses.create_geofence(geofence_params) do
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
