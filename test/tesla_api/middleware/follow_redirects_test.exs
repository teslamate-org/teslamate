defmodule TeslaApi.Middleware.FollowRedirectsTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Middleware.FollowRedirects

  test "strips authorization and host headers case-insensitively on cross-origin redirects" do
    parent = self()
    secret = "secret-access-token"

    adapter = fn
      %Tesla.Env{url: "https://owner-api.teslamotors.com/start"} = env ->
        {:ok,
         %{
           env
           | status: 302,
             headers: [{"location", "https://fleet-api.prd.na.vn.cloud.tesla.com/next"}]
         }}

      %Tesla.Env{url: "https://fleet-api.prd.na.vn.cloud.tesla.com/next"} = env ->
        send(parent, {:redirected_headers, env.headers})
        {:ok, %{env | status: 200, headers: [], body: nil}}
    end

    env = %Tesla.Env{
      method: :get,
      url: "https://owner-api.teslamotors.com/start",
      headers: [
        {"Authorization", "Bearer #{secret}"},
        {"authorization", "Bearer lowercase-token"},
        {"Host", "owner-api.teslamotors.com"},
        {"host", "owner-api.teslamotors.com"},
        {"x-request-id", "request-id"}
      ]
    }

    assert {:ok, %Tesla.Env{status: 200}} = FollowRedirects.call(env, fn: adapter)
    assert_receive {:redirected_headers, headers}

    refute {"Authorization", "Bearer #{secret}"} in headers
    refute {"authorization", "Bearer lowercase-token"} in headers
    refute {"Host", "owner-api.teslamotors.com"} in headers
    refute {"host", "owner-api.teslamotors.com"} in headers
    assert {"x-request-id", "request-id"} in headers
  end
end
