defmodule TeslaApiTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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

  test "filters capitalized authorization headers from debug logs" do
    secret = "secret-access-token"

    level = Logger.level()
    Logger.configure(level: :debug)

    log =
      try do
        capture_log(fn ->
          assert {:ok, %Tesla.Env{status: 200}} =
                   Tesla.Middleware.Logger.call(
                     %Tesla.Env{
                       method: :get,
                       url: "https://owner-api.teslamotors.com/api/1/vehicles",
                       headers: [{"Authorization", "Bearer #{secret}"}]
                     },
                     [fn: fn env -> {:ok, %{env | status: 200, headers: [], body: nil}} end],
                     tesla_api_logger_opts()
                   )
        end)
      after
        Logger.configure(level: level)
      end

    refute log =~ secret
    assert log =~ "Authorization: [FILTERED]"
  end

  defp tesla_api_logger_opts do
    TeslaApi.__middleware__()
    |> Enum.find(fn
      {Tesla.Middleware.Logger, :call, [_opts]} -> true
      _middleware -> false
    end)
    |> elem(2)
    |> List.first()
  end
end
