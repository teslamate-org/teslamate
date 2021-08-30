defmodule TeslaApi.Auth do
  use Tesla

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

  defdelegate login(email, password), to: __MODULE__.Login
  defdelegate refresh(auth), to: __MODULE__.Refresh

  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :error
  defp log_level(%Tesla.Env{}), do: :info
end
