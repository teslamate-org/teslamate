defmodule TeslaApi.Auth.RefreshTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias TeslaApi.Auth

  @auth %Auth{token: "qts-access-token", refresh_token: "refresh-token"}

  # The token endpoint answers directly (RFC 6749 §5.1). Following a redirect
  # would resend the refresh token in the request body to the redirect target.
  defp redirect_mock(pid) do
    {Tesla.Adapter.Finch, [],
     call: fn %Tesla.Env{} = env, _opts ->
       send(pid, :request)
       {:ok, %Tesla.Env{env | status: 302, headers: [{"location", "https://example.com/token"}]}}
     end}
  end

  test "does not follow a redirect from the token endpoint" do
    with_mocks [redirect_mock(self())] do
      capture_log(fn ->
        assert {:error, %TeslaApi.Error{reason: :token_refresh}} = Auth.refresh(@auth)
      end)

      assert_received :request
      refute_received :request
    end
  end

  test "logs a redirect from the token endpoint as a failed request" do
    with_mocks [redirect_mock(self())] do
      log = capture_log(fn -> Auth.refresh(@auth) end)

      assert log =~ "-> 302"
    end
  end
end
