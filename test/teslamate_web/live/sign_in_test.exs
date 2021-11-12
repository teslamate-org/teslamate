defmodule TeslaMateWeb.SignInLiveTest do
  use TeslaMateWeb.ConnCase

  defp start_api(name, opts) do
    api_name = :"api_#{name}"

    {:ok, _pid} =
      start_supervised({ApiMock, name: api_name, pid: self(), captcha: opts[:captcha]})

    %{api: {ApiMock, api_name}}
  end

  setup %{test: name, conn: conn} = ctx do
    params = start_api(name, captcha: Map.get(ctx, :captcha, true))
    conn = put_connect_params(conn, params)
    [conn: conn]
  end

  @tag captcha: true
  test "renders sign in form", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/sign_in")

    doc = Floki.parse_document!(html)

    assert [] == Floki.attribute(doc, "[type=username]", "value")
    assert [] == Floki.attribute(doc, "[type=password]", "value")
    assert [] == Floki.attribute(doc, "#credentials_captcha", "value")

    assert [
             {"button",
              [
                {"class", _},
                {"disabled", "disabled"},
                {"phx-disable-with", "Saving..."},
                {"type", "submit"}
              ], ["Sign in"]}
           ] = doc |> Floki.find("[type=submit]")
  end

  @tag captcha: false
  test "validates credentials", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    assert view
           |> element("form button", "Use email and password")
           |> render_click() =~ "Email address"

    assert doc =
             view
             |> render_change(:validate, %{credentials: %{email: "$email", password: "$password"}})
             |> Floki.parse_document!()

    assert ["$email"] == Floki.attribute(doc, "[type=username]", "value")
    assert ["$password"] == Floki.attribute(doc, "[type=password]", "value")
    assert "Sign in" == doc |> Floki.find("[type=submit]") |> Floki.text()
  end

  @tag captcha: false
  test "signs in", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    assert view
           |> element("form button", "Use email and password")
           |> render_click() =~ "Email address"

    render_change(view, :validate, %{credentials: %{email: "$email", password: "$password"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock, :sign_in, "$email", "$password"}

    assert_redirect(view, "/", 1000)
  end

  @tag captcha: true
  test "signs in with captcha", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    assert view
           |> element("form button", "Use email and password")
           |> render_click() =~ "Email address"

    render_change(view, :validate, %{credentials: %{email: "captcha", password: "$password"}})
    render_submit(view, :sign_in, %{})

    render_change(view, :validate, %{captcha: %{code: "ABCD3f"}})

    doc =
      view
      |> render()
      |> Floki.parse_document!()

    assert [{"span", _, [{"svg", _, []}]}] = Floki.find(doc, "#captcha")
    assert ["ABCD3f"] == Floki.attribute(doc, "#captcha_code", "value")

    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock, :sign_in_callback, "captcha", "$password", "ABCD3f"}
    assert_redirect(view, "/", 1000)
  end

  @tag captcha: true
  test "signs in with second factor", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    assert view
           |> element("form button", "Use email and password")
           |> render_click() =~ "Email address"

    render_change(view, :validate, %{credentials: %{email: "$email", password: "$password"}})
    render_submit(view, :sign_in, %{})

    render_change(view, :validate, %{captcha: %{code: "mfa"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock, :sign_in_callback, "$email", "$password", "mfa"}

    assert [
             {"option", [{"value", "000"}], ["Device #1"]},
             {"option", [{"value", "111"}], ["Device #2"]}
           ] ==
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("#mfa_device_id option")

    doc =
      view
      |> render_change(:validate, %{mfa: %{device_id: "111", passcode: "12345"}})
      |> Floki.parse_document!()

    assert [
             {"option", [{"value", "000"}], ["Device #1"]},
             {"option", [{"selected", "selected"}, {"value", "111"}], ["Device #2"]}
           ] == Floki.find(doc, "#mfa_device_id option")

    assert "12345" ==
             doc |> Floki.find("#mfa_passcode") |> Floki.attribute("value") |> Floki.text()

    assert [
             {"div", _,
              [{"select", [{"disabled", "disabled"}, {"id", "mfa_device_id"} | _], _options}]}
           ] =
             view
             |> render_change(:validate, %{mfa: %{device_id: "111", passcode: "123456"}})
             |> Floki.parse_document!()
             |> Floki.find(".is-loading")

    assert_receive {ApiMock, :mfa_callback, ["111", "123456"]}
    assert_redirect(view, "/", 1000)
  end

  test "signs in with api tokens", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    render_change(view, :validate, %{tokens: %{access: "$access", refresh: "$refresh"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock,
                    {:sign_in, %TeslaMate.Auth.Tokens{access: "$access", refresh: "$refresh"}}}

    assert_redirect(view, "/", 1000)
  end
end
