defmodule TeslaMateWeb.SignInLiveTest do
  use TeslaMateWeb.ConnCase

  import TestHelper, only: [eventually: 1]

  defp start_api(name, sign_in) do
    api_name = :"api_#{name}"

    {:ok, _pid} = start_supervised({ApiMock, name: api_name, pid: self(), sign_in: sign_in})

    %{api: {ApiMock, api_name}}
  end

  # The reply of the API's sign-in comes from the test's :sign_in tag.
  setup %{test: name, conn: conn} = context do
    params = start_api(name, Map.get(context, :sign_in, :ok))
    conn = put_connect_params(conn, params)
    [conn: conn]
  end

  defp submit_tokens(conn) do
    assert {:ok, view, _html} = live(conn, "/sign_in")

    render_change(view, :validate, %{tokens: %{access: "$access", refresh: "$refresh"}})
    render_submit(view, :sign_in, %{})

    assert_receive {ApiMock,
                    {:sign_in, %TeslaMate.Auth.Tokens{access: "$access", refresh: "$refresh"}}}

    view
  end

  test "signs in with api tokens", %{conn: conn} do
    view = submit_tokens(conn)

    assert_redirect(view, "/", 1000)
  end

  @tag sign_in: {:error, %TeslaApi.Error{reason: :invalid_tokens, message: "login_required"}}
  test "says the tokens are invalid if the auth server rejects them", %{conn: conn} do
    view = submit_tokens(conn)

    eventually(fn -> assert render(view) =~ "Tokens are invalid" end)
  end

  @tag sign_in:
         {:error,
          %TeslaApi.Error{reason: :token_refresh, message: "redirected to https://example.com"}}
  test "names the cause if the tokens could not be checked", %{conn: conn} do
    view = submit_tokens(conn)

    eventually(fn ->
      assert render(view) =~ "Token refresh failed: redirected to https://example.com"
    end)
  end

  @tag sign_in: {:error, :already_signed_in}
  test "goes to the vehicles if already signed in", %{conn: conn} do
    view = submit_tokens(conn)

    assert_redirect(view, "/", 1000)
  end

  @tag sign_in: {:exit, :boom}
  @tag :capture_log
  test "reports a sign-in that exits instead of crashing the page", %{conn: conn} do
    view = submit_tokens(conn)

    eventually(fn -> assert render(view) =~ "Sign in failed, see the logs for details" end)
  end
end
