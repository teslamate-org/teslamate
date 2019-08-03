defmodule TeslaMateWeb.SettingsLive.Index do
  use Phoenix.LiveView

  alias TeslaMateWeb.SettingsView
  alias TeslaMate.Settings

  @impl true
  def mount(_session, socket) do
    {:ok, put(socket, Settings.get_settings!())}
  end

  @impl true
  def render(assigns), do: SettingsView.render("index.html", assigns)

  @impl true
  def handle_event("change", %{"settings" => params}, %{assigns: assigns} = socket) do
    case Settings.update_settings(assigns.settings, params) do
      {:error, changeset} -> {:noreply, assign(socket, changeset: changeset)}
      {:ok, settings} -> {:noreply, put(socket, settings)}
    end
  end

  defp put(socket, settings) do
    assign(socket, settings: settings, changeset: Settings.change_settings(settings))
  end
end
