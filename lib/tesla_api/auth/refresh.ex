defmodule TeslaApi.Auth.Refresh do
  import TeslaApi.Auth, only: [post: 2]

  alias TeslaApi.{Auth, Error}
  alias TeslaApi.Auth.OwnerApi

  @web_client_id TeslaApi.Auth.web_client_id()

  def refresh(%Auth{} = auth) do
    with {:ok, %{access_token: _} = tokens} <-
           refresh_oauth_access_token(auth.token, auth.refresh_token),
         {:ok, auth} <- OwnerApi.get_api_tokens(tokens) do
      {:ok, auth}
    else
      error ->
        Error.into(error, :token_refresh)
    end
  end

  defp refresh_oauth_access_token(access_token, refresh_token) do
    data = %{
      grant_type: "refresh_token",
      scope: "openid email offline_access",
      client_id: @web_client_id,
      refresh_token: refresh_token
    }

    base_url =
      case access_token do
        "cn-" <> _ -> "https://auth.tesla.cn"
        _qts -> nil
      end

    case post("#{base_url}/oauth2/v3/token", data) do
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{"access_token" => access_token, "refresh_token" => refresh_token}
       }} ->
        {:ok, %{access_token: access_token, refresh_token: refresh_token}}

      error ->
        error
    end
  end
end
