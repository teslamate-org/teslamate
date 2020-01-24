defmodule TeslaMateWeb.GeoFenceLive.Index do
  use Phoenix.LiveView

  alias TeslaMate.{Locations, Settings}
  alias Settings.GlobalSettings
  alias TeslaMateWeb.GeoFenceView

  @impl true
  def render(assigns), do: GeoFenceView.render("index.html", assigns)

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Gettext.put_locale(session["locale"])

    unit_of_length =
      case Settings.get_global_settings!() do
        %GlobalSettings{unit_of_length: :km} -> :m
        %GlobalSettings{unit_of_length: :mi} -> :ft
      end

    assigns = %{
      geofences: Locations.list_geofences(),
      unit_of_length: unit_of_length
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, %{assigns: %{geofences: geofences}} = socket) do
    {:ok, deleted_geofence} =
      Locations.get_geofence!(id)
      |> Locations.delete_geofence()

    geofences = Enum.reject(geofences, &(&1.id == deleted_geofence.id))

    {:noreply, assign(socket, geofences: geofences)}
  end
end
