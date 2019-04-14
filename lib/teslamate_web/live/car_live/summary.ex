defmodule TeslaMateWeb.CarLive.Summary do
  use Phoenix.LiveView

  import TeslaMateWeb.Gettext

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMateWeb.CarView
  alias TeslaMate.Vehicles

  @impl true
  def mount(%{id: id}, socket) do
    if connected?(socket), do: Vehicles.subscribe(id)

    {:ok, fetch(socket, id)}
  end

  @impl true
  def render(assigns) do
    CarView.render("summary.html", assigns)
  end

  @impl true
  def handle_info(summary, socket) do
    {:noreply, assign(socket, summary: summary, state_t: translate(summary.state))}
  end

  defp fetch(socket, id) do
    summary = Vehicles.summary(id)
    assign(socket, summary: summary, state_t: translate(summary.state))
  end

  # needed for gettext to pick up msgids at compile time
  [
    gettext("driving"),
    gettext("charging"),
    gettext("charging_complete"),
    gettext("updating"),
    gettext("suspended"),
    gettext("online"),
    gettext("offline"),
    gettext("asleep")
  ]

  defp translate(state), do: Gettext.gettext(TeslaMateWeb.Gettext, Atom.to_string(state))
end
