defmodule TeslaApi do
  use Tesla

  @version Mix.Project.config()[:version]

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 35_000

  plug Tesla.Middleware.BaseUrl, "https://owner-api.teslamotors.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]
  plug Tesla.Middleware.JSON
  plug TeslaApi.Middleware.TokenAuth
  plug Tesla.Middleware.Logger, debug: true, log_level: &log_level/1

  defp log_level(%Tesla.Env{} = env) when env.status >= 500, do: :warn
  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :info
  defp log_level(%Tesla.Env{}), do: :debug
end
