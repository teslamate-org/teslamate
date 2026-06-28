defmodule TeslaMateWeb.SupportControllerTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Log

  describe "GET /settings/support-bundle.json" do
    test "downloads the redacted support bundle as JSON", %{conn: conn} do
      {:ok, _car} =
        Log.create_car(%{
          efficiency: 0.153,
          eid: 4242,
          model: "M3",
          name: "Private Vehicle Name",
          vid: 2424,
          vin: "5YJREDACTEDVIN123"
        })

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/settings/support-bundle.json")

      body = response(conn, 200)
      payload = Jason.decode!(body)
      headers = Enum.into(conn.resp_headers, %{})

      assert response_content_type(conn, :json) =~ "charset=utf-8"

      assert headers["content-disposition"] ==
               ~s(attachment; filename="teslamate-support-bundle.json")

      assert payload["schemaVersion"] == 1
      assert payload["redaction"]["mode"] == "allowlist"
      refute body =~ "Private Vehicle Name"
      refute body =~ "5YJREDACTEDVIN123"
    end
  end
end
