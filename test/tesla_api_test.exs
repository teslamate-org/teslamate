defmodule TeslaApiTest do
  use ExUnit.Case, async: true

  test "redacts token query params from request logs" do
    secret = "secret-query-token"

    log =
      %Tesla.Env{
        method: :get,
        url: "https://owner-api.teslamotors.com/api/1/vehicles/1/vehicle_data?token=#{secret}"
      }
      |> TeslaApi.format_log({:ok, %Tesla.Env{status: 408}}, 18_345)
      |> IO.iodata_to_binary()

    refute log =~ secret
    assert log =~ "redacted"
    assert log =~ "GET https://owner-api.teslamotors.com"
    assert log =~ "-> 408"
  end
end
