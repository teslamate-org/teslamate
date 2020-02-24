defmodule TeslaMateWeb.Plugs.SetLocale do
  use Plug.Builder

  alias TeslaMateWeb.Plugs.AcceptLanguage

  plug Cldr.Plug.SetLocale,
    apps: [:cldr, :gettext],
    gettext: TeslaMateWeb.Gettext,
    cldr: TeslaMateWeb.Cldr

  plug AcceptLanguage,
    cldr_backend: TeslaMateWeb.Cldr

  plug :put_locale

  defp put_locale(conn, _opts) do
    %Cldr.LanguageTag{gettext_locale_name: locale} =
      Cldr.Plug.SetLocale.get_cldr_locale(conn) || TeslaMateWeb.Cldr.default_locale()

    put_session(conn, :locale, locale)
  end
end
