defmodule TeslaMateWeb.CarLive.Index do
  use Phoenix.LiveView

  require Logger

  alias TeslaMateWeb.CarView
  alias TeslaMate.{Settings, Log}

  @impl true
  def mount(_session, socket) do
    settings =
      Settings.get_settings!()
      |> update_base_url(socket)

    socket =
      socket
      |> assign_new(:cars, fn -> Log.list_cars() end)
      |> assign_new(:settings, fn -> settings end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    CarView.render("index.html", assigns)
  end

  ## Private

  defp update_base_url(%Settings.Settings{base_url: url} = settings, socket)
       when is_nil(url) or url == "" do
    if connected?(socket) do
      base_url = get_connect_params(socket)["baseUrl"]

      case Settings.update_settings(settings, %{base_url: base_url}) do
        {:error, reason} ->
          Logger.warn("Updating settings failed: #{inspect(reason)}")
          settings

        {:ok, settings} ->
          settings
      end
    else
      settings
    end
  end

  defp update_base_url(settings, _socket) do
    settings
  end
end
