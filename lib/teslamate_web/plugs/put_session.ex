defmodule TeslaMateWeb.Plugs.PutSession do
  @moduledoc """
  Puts the CLDR and Gettext locale names in the session.

  Based on https://github.com/elixir-cldr/cldr/blob/v2.24.1/lib/cldr/plug/plug_put_session.ex

  Differences: besides the :canonical_locale_name ("en_US") that is put in the
  session under the "cldr_locale" key, it also puts the :gettext_locale_name
  ("en") under "gettext_locale".
  """

  import Plug.Conn
  alias Cldr.Plug.SetLocale

  @doc false
  def init(_options) do
    []
  end

  @doc false
  def call(conn, _options) do
    case SetLocale.get_cldr_locale(conn) do
      %Cldr.LanguageTag{canonical_locale_name: cldr_locale, gettext_locale_name: gettext_locale} ->
        conn
        |> fetch_session()
        |> put_session(SetLocale.session_key(), cldr_locale)
        |> put_session("gettext_locale", gettext_locale)

      _other ->
        conn
    end
  end
end
