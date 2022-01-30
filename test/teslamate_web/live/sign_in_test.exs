defmodule TeslaMateWeb.SignInLiveTest do
  use TeslaMateWeb.ConnCase

  defp start_api(name) do
    api_name = :"api_#{name}"

    {:ok, _pid} = start_supervised({ApiMock, name: api_name, pid: self()})

    %{api: {ApiMock, api_name}}
  end

  setup %{test: name, conn: conn} do
    params = start_api(name)
    conn = put_connect_params(conn, params)
    [conn: conn]
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
