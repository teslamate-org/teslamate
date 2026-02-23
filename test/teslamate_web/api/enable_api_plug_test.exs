defmodule TeslaMateWeb.Api.EnableApiPlugTest do
  use TeslaMateWeb.ApiCase

  alias TeslaMateWeb.Api.EnableApiPlug

  describe "call/2" do
    test "passes through when API is enabled", %{conn: conn} do
      Application.put_env(:teslamate, :api, enabled: true, auth_token: "t", jwt_secret: "s")

      conn = EnableApiPlug.call(conn, [])

      refute conn.halted
    end

    test "returns 404 when API is disabled", %{conn: conn} do
      original = Application.get_env(:teslamate, :api)
      Application.put_env(:teslamate, :api, enabled: false, auth_token: "t", jwt_secret: "s")

      conn = EnableApiPlug.call(conn, [])

      assert conn.halted
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "API is not enabled"}

      Application.put_env(:teslamate, :api, original)
    end

    test "returns 404 when API config is nil", %{conn: conn} do
      original = Application.get_env(:teslamate, :api)
      Application.put_env(:teslamate, :api, auth_token: "t", jwt_secret: "s")

      conn = EnableApiPlug.call(conn, [])

      assert conn.halted
      assert conn.status == 404

      Application.put_env(:teslamate, :api, original)
    end
  end
end
