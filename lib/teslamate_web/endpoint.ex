defmodule TeslaMateWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :teslamate

  @session_options [
    store: :cookie,
    key: "_teslamate_key",
    signing_salt: "yt5O3CAQ",
    same_site: "Strict"
  ]

  plug TeslaMateWeb.HealthCheck

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options], transport_log: :debug]

  @only ~w(assets fonts images favicon.ico robots.txt android-chrome-192x192.png
           android-chrome-512x512.png apple-touch-icon.png browserconfig.xml
           favicon-16x16.png favicon-32x32.png mstile-150x150.png
           safari-pinned-tab.svg site.webmanifest)

  plug Plug.Static, at: "/", from: :teslamate, gzip: true, only: @only

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :teslamate
  end

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TeslaMateWeb.Router
end
