defmodule TeslaMateWeb.GeoFenceLive.Index do
  use TeslaMateWeb, :live_view

  alias TeslaMate.{Locations, Settings}
  alias Settings.GlobalSettings

  alias TeslaMate.Convert

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    unit_of_length =
      case settings do
        %GlobalSettings{unit_of_length: :km} -> :m
        %GlobalSettings{unit_of_length: :mi} -> :ft
      end

    assigns = %{
      geofences: Locations.list_geofences(),
      unit_of_length: unit_of_length,
      page_title: gettext("Geo-Fences")
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
