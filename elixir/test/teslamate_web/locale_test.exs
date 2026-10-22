defmodule TeslaMateWeb.LocaleTest do
  use TeslaMateWeb.ConnCase

  defp html_lang(html) do
    html
    |> Floki.parse_document!()
    |> Floki.attribute("html", "lang")
  end

  test "defaults to English", %{conn: conn} do
    conn = get(conn, "/settings")
    html = html_response(conn, 200)

    assert html_lang(html) == ["en"]
    assert html =~ "Settings"
  end

  test "negotiates Accept-Language against Gettext locales", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "de-DE,de;q=0.9,en;q=0.8")
      |> get("/settings")

    html = html_response(conn, 200)

    assert html_lang(html) == ["de"]
    assert html =~ "Einstellungen"
  end

  test "query param beats Accept-Language", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "de")
      |> get("/settings?locale=fr")

    html = html_response(conn, 200)

    assert html_lang(html) == ["fr"]
    assert html =~ "Réglages"
  end

  test "unknown query locale falls back to the default", %{conn: conn} do
    conn = get(conn, "/settings?locale=xx")
    html = html_response(conn, 200)

    assert html_lang(html) == ["en"]
    assert html =~ "Settings"
  end

  test "non-binary locale params are ignored", %{conn: conn} do
    conn = get(conn, "/settings?locale[]=de")
    html = html_response(conn, 200)

    assert html_lang(html) == ["en"]
    assert html =~ "Settings"
  end

  test "the und locale falls back to the default", %{conn: conn} do
    conn = get(conn, "/settings?locale=und")
    html = html_response(conn, 200)

    assert html_lang(html) == ["en"]
    assert html =~ "Settings"
  end

  test "valid but unsupported query locale falls back to the default", %{conn: conn} do
    conn = get(conn, "/settings?locale=pt")
    html = html_response(conn, 200)

    assert html_lang(html) == ["en"]
    assert html =~ "Settings"
  end

  test "unsupported Accept-Language falls back to the default", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "ru-RU,ru;q=0.9")
      |> get("/settings")

    html = html_response(conn, 200)

    assert html_lang(html) == ["en"]
    assert html =~ "Settings"
  end

  test "related languages fall back within the strict distance", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "nn")
      |> get("/settings")

    html = html_response(conn, 200)

    assert html_lang(html) == ["nb"]
    assert html =~ "Innstillinger"
  end

  test "unsupported primary language falls through to a supported secondary", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "ru,de;q=0.9")
      |> get("/settings")

    html = html_response(conn, 200)

    assert html_lang(html) == ["de"]
    assert html =~ "Einstellungen"
  end

  test "preserves Chinese script variants with BCP 47 lang tags", %{conn: conn} do
    html = conn |> get("/settings?locale=zh_Hans") |> html_response(200)
    assert html_lang(html) == ["zh-Hans"]
    assert html =~ "设置"

    html = build_conn() |> get("/settings?locale=zh_Hant") |> html_response(200)
    assert html_lang(html) == ["zh-Hant"]
    assert html =~ "設定"
  end

  test "session persists the locale across requests", %{conn: conn} do
    conn = get(conn, "/settings?locale=de")
    assert html_lang(html_response(conn, 200)) == ["de"]

    conn = conn |> recycle() |> get("/settings")
    html = html_response(conn, 200)

    assert html_lang(html) == ["de"]
    assert html =~ "Einstellungen"
  end

  test "sessions from before the localize migration keep their locale", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{"gettext_locale" => "de"})
      |> get("/settings")

    html = html_response(conn, 200)

    assert html_lang(html) == ["de"]
    assert html =~ "Einstellungen"
  end

  defp mount_locale(session) do
    {:cont, socket} =
      TeslaMateWeb.InitAssigns.on_mount(:locale, %{}, session, %Phoenix.LiveView.Socket{})

    socket.assigns.locale
  end

  test "LiveView mounts apply the session locale" do
    assert mount_locale(%{TeslaMateWeb.Plugs.Locale.session_key() => "de"}) == "de"
  end

  test "LiveView mounts ignore legacy nil and stale session locales" do
    assert mount_locale(%{TeslaMateWeb.Plugs.Locale.session_key() => nil}) == "en"
    assert mount_locale(%{TeslaMateWeb.Plugs.Locale.session_key() => "xx"}) == "en"
  end

  test "supported_locales config stays in sync with the Gettext locales" do
    configured = TeslaMateWeb.Plugs.Locale.gettext_locales() |> Enum.sort()

    gettext = TeslaMateWeb.Gettext |> Gettext.known_locales() |> Enum.sort()

    assert configured == gettext
  end
end
