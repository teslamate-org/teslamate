defmodule TeslaMateWeb.Plugs.PutLocaleInSession do
  @moduledoc """
  Puts the CLDR and Gettext locale names in the session.

  (Based on Cldr.Plug.PutSession)
  """

  import Plug.Conn
  alias Cldr.Plug.SetLocale

  @doc false
  def init(_options), do: []

  @doc false
  def call(conn, _options) do
    case SetLocale.get_cldr_locale(conn) do
      %Cldr.LanguageTag{} = tag ->
        conn
        |> fetch_session()
        |> put_session(SetLocale.session_key(), tag.cldr_locale_name)
        |> put_session("locale", tag.gettext_locale_name)

      _other ->
        conn
    end
  end
end
