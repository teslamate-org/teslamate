defmodule TeslaMateWeb.GeoFenceLive.Index do
  use Phoenix.LiveView

  alias TeslaMate.Addresses
  alias TeslaMateWeb.GeoFenceView

  def render(assigns), do: GeoFenceView.render("index.html", assigns)

  def mount(_session, socket) do
    {:ok, assign(socket, geofences: Addresses.list_geofences(), flagged: nil)}
  end

  def handle_event("flag", id, socket) do
    {:noreply, assign(socket, flagged: id)}
  end

  def handle_event("cancel", id, %{assigns: %{flagged: id}} = socket) do
    {:noreply, assign(socket, flagged: nil)}
  end

  def handle_event("delete", id, socket) do
    geofence = Addresses.get_geofence!(id)
    {:ok, geofence} = Addresses.delete_geofence(geofence)
    geofences = Enum.reject(socket.assigns.geofences, &(&1.id == geofence.id))

    {:noreply, assign(socket, geofences: geofences, flagged: nil)}
  end
end
