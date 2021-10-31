defmodule TeslaApi.Auth.OwnerApi do
  import TeslaApi.Auth, only: [post: 3]

  alias TeslaApi.{Auth, Error}

  @client_id "81527cff06843c8634fdc09e8ac0abefb46ac849f38fe1e431c2ef2106796384"
  @client_secret "c7257eb71a564034f9419ee651c7d0e5f7aa6bfbd18bafb5c5c033b093bb2fa3"

  def exchange_sso_token(%Auth{} = sso_auth) do
    data = %{
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      client_id: @client_id,
      client_secret: @client_secret
    }

    headers = [{"Authorization", "Bearer #{sso_auth.token}"}]

    case post("https://owner-api.teslamotors.com/oauth/token", data, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        auth = %Auth{
          token: body["access_token"],
          type: body["token_type"],
          expires_in: body["expires_in"],
          refresh_token: sso_auth.refresh_token,
          created_at: body["created_at"]
        }

        {:ok, auth}

      error ->
        Error.into(error, :api_token_error)
    end
  end
end
