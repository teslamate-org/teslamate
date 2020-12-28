defmodule TeslaMateWeb.SignInLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Auth.Credentials

  test "renders sign in form", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/sign_in")

    assert html =~ ~r(<input .* type="username"/>)
    assert html =~ ~r(<input .* type="password"/>)
    assert html =~ ~r(<button .* type="submit" disabled="disabled">Sign in</button>)
  end

  test "validates credentials", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    assert html =
             render_change(view, :validate, %{
               credentials: %{email: "$email", password: "$password"}
             })

    assert html =~ ~r(<input .* type="username" value="\$email"/>)
    assert html =~ ~r(<input .* type="password" value="\$password"/>)
    assert html =~ ~r(<button .* type="submit">Sign in</button>)
  end

  defp start_api(name) do
    api_name = :"api_#{name}"
    {:ok, _pid} = start_supervised({ApiMock, name: api_name, pid: self()})
    %{api: {ApiMock, api_name}}
  end

  test "signs in", %{conn: conn, test: name} do
    params = start_api(name)

    assert {:ok, view, _html} =
             conn
             |> put_connect_params(params)
             |> live("/sign_in")

    render_change(view, :validate, %{credentials: %{email: "$email", password: "$password"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock, {:sign_in, %Credentials{email: "$email", password: "$password"}}}
    assert_redirect(view, "/", 1000)
  end

  test "signs in with second factor", %{conn: conn, test: name} do
    params = start_api(name)

    assert {:ok, view, _html} =
             conn
             |> put_connect_params(params)
             |> live("/sign_in")

    render_change(view, :validate, %{credentials: %{email: "mfa", password: "$password"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock, {:sign_in, %Credentials{email: "mfa", password: "$password"}}}

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
             {"option", [{"value", "111"}, {"selected", "selected"}], ["Device #2"]}
           ] == Floki.find(doc, "#mfa_device_id option")

    assert "12345" ==
             doc |> Floki.find("#mfa_passcode") |> Floki.attribute("value") |> Floki.text()

    assert [{"div", _, [{"select", [{"id", "mfa_device_id"} | _], _options}]}] =
             view
             |> render_change(:validate, %{mfa: %{device_id: "111", passcode: "123456"}})
             |> Floki.parse_document!()
             |> Floki.find(".is-loading")

    assert_receive {ApiMock, {:sign_in, "111", "123456", %TeslaApi.Auth.MFA.Ctx{}}}
    assert_redirect(view, "/", 1000)
  end

  test "offers to sign in via the legacy API", %{conn: conn, test: name} do
    params = start_api(name)

    assert {:ok, view, html} =
             conn
             |> put_connect_params(params)
             |> live("/sign_in")

    assert [] ==
             html
             |> Floki.parse_document!()
             |> Floki.find("#credentials_use_legacy_auth")

    render_change(view, :validate, %{credentials: %{email: "error", password: "…"}})
    render_submit(view, :sign_in, %{})

    assert [{"input", [_, _, {"type", "checkbox"}, {"value", "true"}], []}] =
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("#credentials_use_legacy_auth")

    render_change(view, :validate, %{
      credentials: %{email: "$email", password: "$password", use_legacy_auth: true}
    })

    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock,
                    {:sign_in,
                     %Credentials{email: "$email", password: "$password", use_legacy_auth: true}}}

    assert_redirect(view, "/", 1000)
  end

  test "offers to sign in via the legacy API if 2FA step failed", %{conn: conn, test: name} do
    params = start_api(name)

    assert {:ok, view, _html} =
             conn
             |> put_connect_params(params)
             |> live("/sign_in")

    render_change(view, :validate, %{credentials: %{email: "mfa", password: "$password"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock, {:sign_in, %Credentials{email: "mfa", password: "$password"}}}

    assert [{"div", _, [{"select", [{"id", "mfa_device_id"} | _], _options}]}] =
             view
             |> render_change(:validate, %{mfa: %{device_id: "error", passcode: "999999"}})
             |> Floki.parse_document!()
             |> Floki.find(".is-loading")

    assert_receive {ApiMock, {:sign_in, "error", "999999", %TeslaApi.Auth.MFA.Ctx{}}}

    assert [{"button", _, [_icon, " ", {"span", _, ["Use legacy authentication API"]}]}] =
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("button[phx-click='use_legacy_login']")

    assert [{"input", [_, _, {"type", "checkbox"}, {"value", "true"}, {"checked", "checked"}], _}] =
             view
             |> render_click(:use_legacy_login)
             |> Floki.parse_document!()
             |> Floki.find("#credentials_use_legacy_auth")
  end
end
