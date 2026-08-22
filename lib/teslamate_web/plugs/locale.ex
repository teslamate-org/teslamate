defmodule TeslaMateWeb.Plugs.Locale do
  @moduledoc """
  Strict locale sources for `Localize.Plug.PutLocale`, plus the plug that
  applies the negotiated locale to Gettext and the session.

  `Localize.validate_locale/1` matches at the default CLDR distance (80),
  which never fails for a syntactically valid tag: an unrelated language
  best-matches onto the *first* supported locale as a last resort, so
  `Accept-Language: ru` would come back Catalan instead of falling
  through to the default. The sources here match strictly — distance 79
  keeps CLDR's genuine related-language fallbacks (such as `nn` -> `nb`)
  but rejects the unrelated-language bucket — and return `nil` on no
  match, so the plug moves on to the next source and ultimately the
  configured default. Accept-Language entries are tried per tag in
  quality order, so an unsupported primary language still falls through
  to a supported secondary preference.

  The session stores the Gettext locale name under `"gettext_locale"`,
  the same contract the pre-Localize `PutSession` plug used: sessions
  written before the migration stay valid, and the LiveView `on_mount`
  hook remains a plain `Gettext.put_locale/2` without re-running the
  negotiation.
  """

  import Plug.Conn

  @behaviour Plug

  @session_key "gettext_locale"
  @strict_distance Localize.LanguageTag.default_distance() - 1

  # The supported CLDR ids map 1:1 onto the Gettext locale names
  # (`priv/gettext/*`); `locale_test.exs` asserts the two sets stay
  # in sync.
  @gettext_locales Map.new(
                     Application.compile_env!(:localize, :supported_locales),
                     &{&1, &1 |> Atom.to_string() |> String.replace("-", "_")}
                   )
  @cldr_locales Map.new(@gettext_locales, fn {cldr, gettext} -> {gettext, cldr} end)

  @doc false
  def session_key, do: @session_key

  @doc false
  def gettext_locales, do: Map.values(@gettext_locales)

  ## Locale sources for Localize.Plug.PutLocale

  @doc false
  def from_query(%Plug.Conn{query_params: %Plug.Conn.Unfetched{}} = conn, options) do
    from_query(fetch_query_params(conn), options)
  end

  def from_query(conn, _options) do
    strict_match(conn.query_params["locale"])
  end

  @doc false
  def from_session(conn, _options) do
    strict_match(get_session(conn, @session_key))
  end

  @doc false
  def from_accept_language(conn, _options) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        header
        |> Localize.AcceptLanguage.tokenize()
        |> Enum.find_value(fn {_quality, tag} -> strict_match(tag) end)

      [] ->
        nil
    end
  end

  # Exact Gettext locale names (session values, `?locale=` from the
  # settings UI) resolve through the compile-time map without any tag
  # matching; everything else pays one strict `best_match` against the
  # supported list.
  defp strict_match(locale) when is_binary(locale) do
    case Map.fetch(@cldr_locales, locale) do
      {:ok, cldr_id} ->
        validated(cldr_id)

      :error ->
        case Localize.LanguageTag.best_match(
               locale,
               Localize.supported_locales(),
               @strict_distance
             ) do
          {:ok, cldr_id, _score} -> validated(cldr_id)
          {:error, _reason} -> nil
        end
    end
  end

  # nil (no value) or anything non-binary — `?locale[]=de` decodes to a
  # list — is never a locale; fall through to the next source.
  defp strict_match(_other), do: nil

  defp validated(cldr_id) do
    case Localize.validate_locale(cldr_id) do
      {:ok, _language_tag} = ok -> ok
      {:error, _reason} -> nil
    end
  end

  ## Plug: apply the locale Localize.Plug.PutLocale resolved

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _options) do
    case Localize.Plug.PutLocale.get_locale(conn) do
      %Localize.LanguageTag{cldr_locale_id: cldr_id} when is_map_key(@gettext_locales, cldr_id) ->
        locale = Map.fetch!(@gettext_locales, cldr_id)
        Gettext.put_locale(TeslaMateWeb.Gettext, locale)

        # :html_lang, not :locale — LiveView merges its assigns (where
        # :locale is the Gettext name, e.g. "zh_Hans") into the conn
        # assigns on the dead render and would shadow this one.
        conn
        |> put_session(@session_key, locale)
        |> assign(:html_lang, Atom.to_string(cldr_id))

      _other ->
        conn
    end
  end
end
