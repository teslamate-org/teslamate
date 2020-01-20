defmodule TeslaMateWeb.LocalePlug do
  import Plug.Conn

  @max_age 365 * 24 * 60 * 60

  def init(opts) do
    [backend: Keyword.fetch!(opts, :backend)]
  end

  def call(conn, backend: backend) do
    case fetch_locale(conn, backend) do
      nil ->
        conn
        |> put_session(:locale, Gettext.get_locale(backend))

      locale ->
        Gettext.put_locale(backend, locale)

        conn
        |> put_session(:locale, locale)
        |> put_resp_header("content-language", locale_to_language(locale))
        |> put_resp_cookie("locale", locale, max_age: @max_age)
    end
  end

  defp fetch_locale(conn, backend) do
    fetch_locale_from_params(conn, backend) ||
      fetch_locale_from_cookies(conn, backend) ||
      fetch_locale_from_headers(conn, backend)
  end

  defp fetch_locale_from_params(conn, backend) do
    conn.params["locale"] |> validate_locale(backend)
  end

  defp fetch_locale_from_cookies(conn, backend) do
    conn.cookies["locale"] |> validate_locale(backend)
  end

  defp fetch_locale_from_headers(conn, backend) do
    conn |> locales_from_accept_language() |> Enum.find(&validate_locale(&1, backend))
  end

  defp locales_from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [value | _] ->
        values = String.split(value, ",")
        Enum.map(values, &resolve_locale_from_accept_language/1)

      _ ->
        []
    end
  end

  defp resolve_locale_from_accept_language(language) do
    language
    |> String.split(";")
    |> List.first()
    |> language_to_locale()
  end

  defp language_to_locale(language), do: String.replace(language, "-", "_", global: false)
  defp locale_to_language(locale), do: String.replace(locale, "_", "-", global: false)

  defp validate_locale(nil, _), do: nil

  defp validate_locale(locale, backend) do
    if locale in Gettext.known_locales(backend) do
      locale
    end
  end
end
