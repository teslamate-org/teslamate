defmodule TeslaMateWeb.Plugs.SetLocale do
  use Plug.Builder

  require TeslaMateWeb.Cldr
  alias TeslaMateWeb.Plugs.AcceptLanguage

  plug AcceptLanguage,
    cldr_backend: TeslaMateWeb.Cldr

  plug Cldr.Plug.SetLocale,
    apps: [:cldr, :gettext],
    from: [:query, :session, :accept_language],
    gettext: TeslaMateWeb.Gettext,
    cldr: TeslaMateWeb.Cldr

  plug Cldr.Plug.SetSession
end
