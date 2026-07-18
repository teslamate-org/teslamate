defmodule TeslaMateWeb.Plugs.OperationsAuthTest do
  use TeslaMateWeb.ConnCase

  alias Plug.BasicAuth

  setup do
    previous = Application.get_env(:teslamate, :operations_auth)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:teslamate, :operations_auth)
      else
        Application.put_env(:teslamate, :operations_auth, previous)
      end
    end)

    :ok
  end

  test "leaves the read-only maintenance route public", %{conn: conn} do
    Application.put_env(:teslamate, :operations_auth, required: false)

    conn = get(conn, "/maintenance")

    assert html_response(conn, 200) =~ "Maintenance"
    assert get_resp_header(conn, "www-authenticate") == []
    assert ["no-store"] = get_resp_header(conn, "cache-control")
  end

  test "challenges sensitive operations and accepts valid credentials", %{conn: conn} do
    Application.put_env(:teslamate, :operations_auth,
      required: true,
      username: "operator",
      password: "secret"
    )

    unauthorized = get(conn, "/maintenance")

    assert response(unauthorized, 401) == "Unauthorized"

    assert [~s(Basic realm="TeslaMate Operations")] =
             get_resp_header(unauthorized, "www-authenticate")

    assert ["no-store"] = get_resp_header(unauthorized, "cache-control")

    authorized =
      build_conn()
      |> put_req_header("authorization", BasicAuth.encode_basic_auth("operator", "secret"))
      |> get("/maintenance")

    assert html_response(authorized, 200) =~ "Maintenance"
    assert ["no-store"] = get_resp_header(authorized, "cache-control")
  end

  test "fails closed when credentials are missing", %{conn: conn} do
    Application.put_env(:teslamate, :operations_auth, required: true)

    conn = get(conn, "/maintenance")

    assert response(conn, 503) == "Operations authentication is not configured"
    assert conn.halted
    assert ["no-store"] = get_resp_header(conn, "cache-control")
  end
end
