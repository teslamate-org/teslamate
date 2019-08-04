defmodule TeslaMateWeb.CarLive.Index do
  use Phoenix.LiveView

  alias TeslaMateWeb.CarView
  alias TeslaMate.{Settings, Log}

  @impl true
  def mount(_session, socket) do
    socket =
      socket
      |> assign_new(:cars, fn -> Log.list_cars() end)
      |> assign_new(:settings, fn -> Settings.get_settings!() end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    CarView.render("index.html", assigns)
  end
end
