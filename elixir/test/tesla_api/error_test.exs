defmodule TeslaApi.ErrorTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Error

  test "redacts access tokens when inspected" do
    secret = "secret-access-token"

    {:error, error} =
      Error.into(
        {:ok,
         %Tesla.Env{
           method: :get,
           url: "https://owner-api.teslamotors.com/api/1/vehicles/1/vehicle_data?token=#{secret}",
           query: [token: secret],
           headers: [{"authorization", "Bearer #{secret}"}],
           opts: [access_token: secret]
         }}
      )

    inspected = inspect(error, pretty: true)

    refute inspected =~ secret
    assert inspected =~ "[redacted]"
  end

  test "redacts access tokens when directly constructed errors are inspected" do
    secret = "secret-access-token"

    error = %Error{
      reason: :vehicle_unavailable,
      env: %Tesla.Env{
        method: :get,
        url: "https://owner-api.teslamotors.com/api/1/vehicles/1/vehicle_data?token=#{secret}",
        query: [token: secret],
        headers: [{"authorization", "Bearer #{secret}"}],
        opts: [access_token: secret]
      }
    }

    inspected = inspect(error, pretty: true)

    refute inspected =~ secret
    assert inspected =~ "[redacted]"
  end

  test "keeps non-sensitive Tesla env details when inspected" do
    {:error, error} =
      Error.into(
        {:ok,
         %Tesla.Env{
           method: :get,
           url: "https://owner-api.teslamotors.com/api/1/vehicles/1/vehicle_data",
           query: [endpoints: "charge_state"],
           headers: [{"x-request-id", "request-id"}],
           opts: [receive_timeout: 35_000]
         }}
      )

    inspected = inspect(error, pretty: true)

    assert inspected =~ "charge_state"
    assert inspected =~ "request-id"
    assert inspected =~ "35000"
  end
end
