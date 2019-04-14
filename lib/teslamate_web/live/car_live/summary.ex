defmodule TeslaMateWeb.CarLive.Summary do
  use Phoenix.LiveView

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
    {:noreply, assign(socket, summary: summary)}
  end

  defp fetch(socket, id) do
    assign(socket, summary: Vehicles.summary(id))
  end
end
