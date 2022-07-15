defmodule TeslaApi.Auth do
  use Tesla

  alias TeslaApi.Error

  @web_client_id "ownerapi"
  @redirect_uri "https://auth.tesla.com/void/callback"

  def web_client_id, do: @web_client_id
  def redirect_uri, do: @redirect_uri

  @default_headers [
    {"user-agent", "TeslaMate/#{Mix.Project.config()[:version]}"},
    {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
    {"Accept-Language", "en-US,de-DE;q=0.5"}
  ]

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 60_000

  plug TeslaApi.Middleware.FollowRedirects, except: [@redirect_uri]
  plug Tesla.Middleware.BaseUrl, "https://auth.tesla.com"
  plug Tesla.Middleware.Headers, @default_headers
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, debug: true, log_level: &log_level/1

  defstruct [:token, :type, :expires_in, :refresh_token, :created_at]

  defdelegate refresh(auth), to: __MODULE__.Refresh

  def issuer_url(%__MODULE__{token: access_token}) do
    case derive_issuer_url_from_oat(access_token) do
      {:ok, issuer_url} ->
        issuer_url

      :error ->
        case decode_jwt_payload(access_token) do
          {:ok, %{"iss" => issuer_url}} -> issuer_url
          _ -> "https://auth.tesla.com/oauth2/v3"
        end
    end
  end

  def region(%__MODULE__{} = auth) do
    tld =
      auth
      |> issuer_url()
      |> URI.parse()
      |> Map.fetch!(:host)
      |> String.split(".")
      |> List.last()

    case tld do
      "cn" -> :chinese
      "com" -> :global
      _other -> :other
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

      {:error, reason} ->
        Error.into({:error, reason}, :invalid_access_token)

      _error ->
        Error.into({:error, "Invalid access token"}, :invalid_access_token)
    end
  end

  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :error
  defp log_level(%Tesla.Env{}), do: :info
end
