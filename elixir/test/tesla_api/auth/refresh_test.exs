defmodule TeslaApi.Auth.RefreshTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias TeslaApi.{Auth, Error}

  @auth %Auth{token: "qts-access-token", refresh_token: "refresh-token"}

  defp adapter_mock(pid, response) do
    {Tesla.Adapter.Finch, [],
     call: fn %Tesla.Env{} = env, _opts ->
       send(pid, :request)

       case response do
         {:error, _reason} = error -> error
         fields -> {:ok, struct(env, Keyword.merge([headers: []], fields))}
       end
     end}
  end

  # Returns the result and the log of one refresh against the given response.
  defp refresh(response) do
    with_mocks [adapter_mock(self(), response)] do
      with_log(fn -> Auth.refresh(@auth) end)
    end
  end

  describe "a successful response" do
    test "returns the new tokens" do
      body = %{
        "access_token" => "access",
        "refresh_token" => "new-refresh",
        "expires_in" => 28_800
      }

      assert {{:ok, %Auth{token: "access", refresh_token: "new-refresh", expires_in: 28_800}}, _} =
               refresh(status: 200, body: body)
    end

    # RFC 6749 §6
    test "keeps the current refresh token if the response brings no new one" do
      body = %{"access_token" => "access", "expires_in" => 28_800}

      assert {{:ok, %Auth{token: "access", refresh_token: "refresh-token"}}, _} =
               refresh(status: 200, body: body)
    end

    test "without an access token or its lifetime is an invalid response" do
      for response <- [
            [status: 200, body: %{"expires_in" => 28_800}],
            [status: 200, body: %{"access_token" => "access"}],
            [status: 200, headers: [{"content-type", "text/html"}], body: "<html></html>"],
            [status: 200, headers: [{"content-type", "application/json"}], body: "<html>"]
          ] do
        assert {{:error, %Error{reason: :token_refresh, message: "invalid token response"}}, _} =
                 refresh(response)
      end
    end
  end

  describe "rejected tokens" do
    test "login_required, which Tesla answers for an expired or cycled-out refresh token" do
      body = %{
        "error" => "login_required",
        "error_description" => "The refresh_token is invalid."
      }

      assert {{:error, %Error{reason: :invalid_tokens} = error}, _} =
               refresh(status: 401, body: body)

      assert error.message == "login_required: The refresh_token is invalid."
    end

    test "invalid_grant" do
      assert {{:error, %Error{reason: :invalid_tokens, message: "invalid_grant"}}, _} =
               refresh(status: 400, body: %{"error" => "invalid_grant"})
    end
  end

  describe "any other failure names its cause" do
    test "another OAuth error, also in a 200" do
      body = %{"error" => "invalid_client", "error_description" => "Unknown client."}

      for status <- [401, 200] do
        assert {{:error,
                 %Error{reason: :token_refresh, message: "invalid_client: Unknown client."}}, _} =
                 refresh(status: status, body: body)
      end
    end

    # The token endpoint answers directly (RFC 6749 §5.1). Following a redirect
    # would resend the refresh token in the request body to the redirect target.
    test "a redirect is not followed" do
      assert {{:error, %Error{reason: :token_refresh}}, _} =
               refresh(status: 302, headers: [{"location", "https://example.com/token"}])

      assert_received :request
      refute_received :request
    end

    test "a redirect target loses userinfo, query and fragment in message and header" do
      location = "https://user:secret@example.com/token?refresh_token=secret#secret"

      assert {{:error, %Error{message: "redirected to https://example.com/token"} = error}, _} =
               refresh(status: 302, headers: [{"location", location}])

      assert Tesla.get_headers(error.env, "location") == ["https://example.com/token"]
    end

    test "a relative redirect names the resolved target" do
      assert {{:error, %Error{message: message}}, _} =
               refresh(status: 301, headers: [{"location", "/moved"}])

      # The base is the auth host, which the environment may override.
      assert message =~ ~r"^redirected to https?://[^/]+/moved$"
    end

    test "a redirect without a location names the status" do
      assert {{:error, %Error{reason: :token_refresh, message: "HTTP 307"}}, _} =
               refresh(status: 307, headers: [])
    end

    test "a redirect is logged as a failed request" do
      {_result, log} = refresh(status: 302, headers: [{"location", "https://example.com/token"}])

      assert log =~ "-> 302"
    end

    test "a server error" do
      assert {{:error, %Error{reason: :token_refresh, message: "HTTP 503"}}, _} =
               refresh(status: 503, body: "")
    end

    test "a transport error" do
      assert {{:error, %Error{reason: :token_refresh, message: "timeout"}}, _} =
               refresh({:error, %Mint.TransportError{reason: :timeout}})
    end
  end

  test "keeps the tokens out of the log, even on the debug level" do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    body = %{"access_token" => "new-access", "refresh_token" => "new-refresh", "expires_in" => 1}

    assert {{:ok, %Auth{}}, log} = refresh(status: 200, body: body)

    assert log =~ "-> 200"

    for token <- ["refresh-token", "new-access", "new-refresh"] do
      refute log =~ token
    end
  end
end
