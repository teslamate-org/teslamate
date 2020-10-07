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

    render_change(view, :validate, %{
      credentials: %{email: "$email", password: "$password"}
    })

    render_submit(view, :save, %{})
    assert_redirect(view, "/")

    assert_receive {ApiMock, {:sign_in, %Credentials{email: "$email", password: "$password"}}}
  end
end
