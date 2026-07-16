defmodule TeslaMateWeb.HealthControllerTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.RuntimeHealth

  test "returns aggregate runtime health without vehicle activity", %{conn: conn} do
    start_supervised!({RuntimeHealth, mqtt_enabled: false})

    :ok = RuntimeHealth.record_summary(42, :driving)
    :ok = RuntimeHealth.record_api(42, {:ok, %{vin: "private"}})
    _report = RuntimeHealth.report()

    conn = get(conn, "/api/health")

    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert %{
             "schema_version" => 1,
             "status" => "ok",
             "mqtt" => %{"status" => "disabled"},
             "vehicles" => %{"total" => 1, "ok" => 1, "degraded" => 0}
           } = json_response(conn, 200)

    refute conn.resp_body =~ "42"
    refute conn.resp_body =~ "driving"
    refute conn.resp_body =~ "private"
    refute conn.resp_body =~ "generated_at"
    refute conn.resp_body =~ "last_"
  end

  test "returns unavailable when the runtime collector is missing", %{conn: conn} do
    conn = get(conn, "/api/health")

    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert %{
             "schema_version" => 1,
             "status" => "unavailable",
             "reason" => "runtime_health_unavailable"
           } = json_response(conn, 503)
  end

  test "preserves the legacy blank health check", %{conn: conn} do
    conn = get(conn, "/health_check")
    assert response(conn, 200) == ""
  end
end
