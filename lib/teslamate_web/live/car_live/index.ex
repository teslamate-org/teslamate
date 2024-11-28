defmodule TeslaMateWeb.CarLive.Index do
  use TeslaMateWeb, :live_view

  require Logger

  alias TeslaMate.{Settings, Vehicles}
  alias TeslaMate.Settings.GlobalSettings

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => settings}, socket) do
    socket =
      socket
      |> assign(page_title: gettext("Home"))
      |> assign_new(:summaries, fn -> Vehicles.list() end)
      |> assign_new(:settings, fn ->
        settings
        |> update_base_url(socket)
        |> update_grafana_url(socket)
      end)

    {:ok, socket}
  end

  ## Private

  defp update_base_url(%GlobalSettings{base_url: url} = settings, socket)
       when is_nil(url) or url == "" do
    if connected?(socket) do
      base_url = get_connect_params(socket)["baseUrl"]

      case Settings.update_global_settings(settings, %{base_url: base_url}) do
        {:error, reason} ->
          Logger.warning("Updating base_url failed: #{inspect(reason)}")
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

  defp update_grafana_url(%GlobalSettings{base_url: url} = settings, socket)
       when is_nil(url) or url == "" do
    settings
  end

  defp update_grafana_url(%GlobalSettings{base_url: url} = settings, socket) do
    if connected?(socket) do
      grafana_url = replace_port(url, 3000)

      case Settings.update_global_settings(settings, %{grafana_url: grafana_url}) do
        {:error, reason} ->
          Logger.warning("Updating grafana_url failed: #{inspect(reason)}")
          settings

        {:ok, settings} ->
          settings
      end
    else
      settings
    end
  end

  defp replace_port(url, new_port) do
    uri = URI.parse(url)
    uri = %URI{uri | port: new_port}
    URI.to_string(uri)
  end
end
