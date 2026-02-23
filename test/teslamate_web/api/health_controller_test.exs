defmodule TeslaMateWeb.Api.HealthControllerTest do
  use TeslaMateWeb.ApiCase

  describe "GET /api/v1/health" do
    test "returns ok status with version", %{conn: conn} do
      conn = get(conn, "/api/v1/health")

      assert %{"status" => "ok", "version" => version} = json_response(conn, 200)
      assert is_binary(version)
    end

    test "does not require authentication", %{conn: conn} do
      # No auth header set - should still succeed
      conn = get(conn, "/api/v1/health")

      assert conn.status == 200
    end
  end
end
