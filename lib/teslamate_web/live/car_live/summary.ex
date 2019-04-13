defmodule TeslaMateWeb.CarLive.Summary do
  use Phoenix.LiveView

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
  def handle_info({state, vehicle}, socket) do
    {:noreply, assign(socket, state: state, vehicle: vehicle)}
  end

  defp fetch(socket, id) do
    {state, vehicle} = Vehicles.state(id, extended: true)
    assign(socket, state: state, vehicle: vehicle)
  end
end
