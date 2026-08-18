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

  test "preserves Chinese script variants", %{conn: conn} do
    html = conn |> get("/settings?locale=zh_Hans") |> html_response(200)
    assert html_lang(html) == ["zh_Hans"]
    assert html =~ "设置"

    html = build_conn() |> get("/settings?locale=zh_Hant") |> html_response(200)
    assert html_lang(html) == ["zh_Hant"]
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
end
