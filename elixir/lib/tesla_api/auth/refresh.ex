defmodule TeslaApi.Auth.Refresh do
  import TeslaApi.Auth, only: [post: 2]

  alias TeslaApi.{Auth, Error}

  @web_client_id TeslaApi.Auth.web_client_id()

  # OAuth error codes meaning the refresh token can no longer be used:
  # invalid_grant per RFC 6749 §5.2, and login_required, which Tesla documents
  # for an expired or cycled-out refresh token and after a password reset.
  @invalid_token_errors ~w(invalid_grant login_required)

  def refresh(%Auth{} = auth) do
    issuer_url =
      if System.get_env("TESLA_AUTH_HOST", "") == "" do
        Auth.issuer_url(auth)
      else
        System.get_env("TESLA_AUTH_HOST", "") <> System.get_env("TESLA_AUTH_PATH", "")
      end

    data = %{
      grant_type: "refresh_token",
      scope: "openid email offline_access",
      client_id: System.get_env("TESLA_AUTH_CLIENT_ID", @web_client_id),
      refresh_token: auth.refresh_token
    }

    "#{issuer_url}/token"
    |> post(data)
    |> handle_response(auth)
  end

  defp handle_response(
         {:ok,
          %Tesla.Env{
            status: 200,
            body: %{"access_token" => token, "expires_in" => expires_in} = body
          }},
         auth
       )
       when is_binary(token) and is_integer(expires_in) do
    {:ok,
     %Auth{
       token: token,
       type: body["token_type"],
       expires_in: expires_in,
       # RFC 6749 §6: without a new refresh token the current one stays valid.
       refresh_token: body["refresh_token"] || auth.refresh_token,
       created_at: body["created_at"]
     }}
  end

  defp handle_response({:ok, %Tesla.Env{body: %{"error" => code} = body} = env}, _auth)
       when code in @invalid_token_errors,
       do: error(:invalid_tokens, oauth_message(code, body), env)

  defp handle_response({:ok, %Tesla.Env{status: status} = env}, _auth) when status in 300..399,
    do: error(:token_refresh, redirect_message(env), env)

  defp handle_response({:ok, %Tesla.Env{status: 200} = env}, _auth),
    do: error(:token_refresh, "invalid token response", env)

  defp handle_response({:ok, %Tesla.Env{body: %{"error" => code} = body} = env}, _auth)
       when is_binary(code),
       do: error(:token_refresh, oauth_message(code, body), env)

  defp handle_response({:ok, %Tesla.Env{status: status} = env}, _auth),
    do: error(:token_refresh, "HTTP #{status}", env)

  defp handle_response({:error, {Tesla.Middleware.JSON, :decode, _reason}}, _auth),
    do: error(:token_refresh, "invalid token response", nil)

  defp handle_response({:error, reason}, _auth),
    do: error(:token_refresh, transport_message(reason), nil)

  defp error(reason, message, env) do
    {:error, Error.redacted(%Error{reason: reason, message: message, env: env})}
  end

  defp oauth_message(code, %{"error_description" => description}) when is_binary(description),
    do: "#{code}: #{description}"

  defp oauth_message(code, _body), do: code

  # Without query and fragment, which can carry credentials.
  defp redirect_message(%Tesla.Env{} = env) do
    case Tesla.get_header(env, "location") do
      nil ->
        "HTTP #{env.status}"

      location ->
        %URI{} = target = URI.merge(env.url, location)
        "redirected to #{%URI{target | query: nil, fragment: nil}}"
    end
  end

  defp transport_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp transport_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp transport_message(reason), do: inspect(reason)
end
