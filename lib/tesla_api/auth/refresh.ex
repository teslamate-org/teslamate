defmodule TeslaApi.Auth.Refresh do
  import TeslaApi.Auth, only: [post: 2]

  alias TeslaApi.{Auth, Error}

  @web_client_id TeslaApi.Auth.web_client_id()

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

    case post(
           "#{issuer_url}/token" <> System.get_env("TOKEN", ""),
           data
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        auth = %Auth{
          token: body["access_token"],
          type: body["token_type"],
          expires_in: body["expires_in"],
          refresh_token: body["refresh_token"],
          created_at: body["created_at"]
        }

        {:ok, auth}

      error ->
        Error.into(error, :token_refresh)
    end
  end
end
