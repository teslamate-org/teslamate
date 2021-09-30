defmodule TeslaApi.Auth.Refresh do
  import TeslaApi.Auth, only: [post: 2]

  alias TeslaApi.{Auth, Error}

  @web_client_id TeslaApi.Auth.web_client_id()

  def refresh(%Auth{} = auth) do
    issuer_url =
      case derive_issuer_url_from_oat(auth.token) do
        {:ok, issuer_url} ->
          issuer_url

        :error ->
          case decode_jwt_payload(auth.token) do
            {:ok, %{"iss" => iss}} -> URI.parse(iss)
            _ -> "https://auth.tesla.com/oauth2/v3"
          end
      end

    data = %{
      grant_type: "refresh_token",
      scope: "openid email offline_access",
      client_id: @web_client_id,
      refresh_token: auth.refresh_token
    }

    case post("#{issuer_url}/token", data) do
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

  defp derive_issuer_url_from_oat("qts-" <> _), do: {:ok, "https://auth.tesla.com/oauth2/v3"}
  defp derive_issuer_url_from_oat("eu-" <> _), do: {:ok, "https://auth.tesla.com/oauth2/v3"}
  defp derive_issuer_url_from_oat("cn-" <> _), do: {:ok, "https://auth.tesla.cn/oauth2/v3"}
  defp derive_issuer_url_from_oat(_), do: :error

  defp decode_jwt_payload(jwt) do
    with [_algo, payload, _signature] <- String.split(jwt, "."),
         {:ok, payload} <- Base.decode64(payload, padding: false),
         {:ok, payload} <- Jason.decode(payload) do
      {:ok, payload}
    else
      l when is_list(l) ->
        Error.into({:error, :invalid_jwt}, :invalid_access_token)

      error ->
        Error.into(error, :invalid_access_token)
    end
  end
end
