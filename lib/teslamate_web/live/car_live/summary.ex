defmodule TeslaMateWeb.CarLive.Summary do
  use Phoenix.LiveView

  import TeslaMateWeb.Gettext

  alias TeslaMateWeb.CarView
  alias TeslaMate.Vehicles

  @impl true
  def mount(%{id: id, settings: settings}, socket) do
    if connected?(socket), do: Vehicles.subscribe(id)

    assigns = %{
      summary: Vehicles.summary(id),
      settings: settings,
      translate_state: &translate_state/1
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    CarView.render("summary.html", assigns)
  end

  @impl true
  def handle_info(summary, socket) do
    {:noreply, assign(socket, summary: summary)}
  end

  defp translate_state(:driving), do: gettext("driving")
  defp translate_state(:charging), do: gettext("charging")
  defp translate_state(:charging_complete), do: gettext("charging complete")
  defp translate_state(:updating), do: gettext("updating")
  defp translate_state(:suspended), do: gettext("falling asleep")
  defp translate_state(:online), do: gettext("online")
  defp translate_state(:offline), do: gettext("offline")
  defp translate_state(:asleep), do: gettext("asleep")
  defp translate_state(:unavailable), do: gettext("unavailable")
end
