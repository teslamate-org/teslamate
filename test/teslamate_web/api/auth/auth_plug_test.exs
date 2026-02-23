defmodule TeslaMateWeb.Api.Auth.PlugTest do
  use TeslaMateWeb.ApiCase

  alias TeslaMateWeb.Api.Auth

  describe "call/2" do
    test "assigns current_user with valid JWT", %{conn: conn} do
      {:ok, jwt, _exp} = Auth.Token.generate_jwt()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> Auth.Plug.call([])

      refute conn.halted
      assert conn.assigns[:current_user] == "api_user"
    end

    test "returns 401 when authorization header is missing", %{conn: conn} do
      conn = Auth.Plug.call(conn, [])

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "Invalid or missing authentication token"}
    end

    test "returns 401 with malformed authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Token some-value")
        |> Auth.Plug.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 with invalid JWT", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> Auth.Plug.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 with expired JWT", %{conn: conn} do
      config = Application.get_env(:teslamate, :api)
      secret = Keyword.fetch!(config, :jwt_secret)
      signer = Joken.Signer.create("HS256", secret)

      expired_exp = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix()
      claims = %{"sub" => "api_user", "exp" => expired_exp}

      {:ok, expired_token, _claims} =
        Joken.generate_and_sign(Auth.Token.token_config(), claims, signer)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{expired_token}")
        |> Auth.Plug.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end
end
