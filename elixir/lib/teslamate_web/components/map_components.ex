defmodule TeslaMateWeb.MapComponents do
  @moduledoc """
  Defines the tile layer of the maps once, for both its consumers: the map
  hooks, which read it from `data-tile-layer`, and the preconnect hint, which
  sets up the connection to the tile server before the hooks mount.
  """

  use Phoenix.Component

  @tile_url "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

  @tile_layer Jason.encode!(%{
                url: @tile_url,
                options: %{
                  maxZoom: 19,
                  attribution:
                    ~s(&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors),
                  referrerPolicy: "strict-origin-when-cross-origin"
                }
              })

  %URI{scheme: scheme, host: host, port: port} = URI.parse(@tile_url)
  @tile_origin URI.to_string(%URI{scheme: scheme, host: host, port: port})

  @doc "The tile layer as JSON for the `data-tile-layer` attribute of a map hook."
  def tile_layer, do: @tile_layer

  @doc "Starts DNS and TLS to the tile server while the page loads."
  def tile_preconnect(assigns) do
    assigns = assign(assigns, :href, @tile_origin)

    ~H"""
    <link rel="preconnect" href={@href} />
    """
  end
end
