defmodule TeslaMateWeb.Api.Auth.AuthControllerTest do
  use TeslaMateWeb.ApiCase

  describe "POST /api/v1/auth/login" do
    test "returns JWT with valid API token", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/login", %{token: "test_api_token"})

      assert %{"jwt" => jwt, "expires_at" => expires_at} = json_response(conn, 200)
      assert is_binary(jwt)
      assert is_integer(expires_at)

      # Verify the returned JWT is valid
      assert {:ok, claims} = TeslaMateWeb.Api.Auth.Token.verify_jwt(jwt)
      assert claims["sub"] == "api_user"
    end

    test "returns 401 with invalid API token", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/login", %{token: "wrong_token"})

      assert %{"error" => "Invalid API token"} = json_response(conn, 401)
    end

    test "returns 400 when token parameter is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/login", %{})

      assert %{"error" => "Missing 'token' parameter"} = json_response(conn, 400)
    end

    test "returns 400 when body is empty", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/login", %{other: "param"})

      assert %{"error" => "Missing 'token' parameter"} = json_response(conn, 400)
    end
  end
end
