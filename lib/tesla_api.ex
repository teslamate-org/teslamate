defmodule TeslaApi do
  @version Mix.Project.config()[:version]

  def client(token) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "https://owner-api.teslamotors.com"},
        {Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]},
        Tesla.Middleware.JSON,
        {TeslaApi.Middleware.TokenAuth, token},
        {Tesla.Middleware.Logger, debug: true, log_level: &log_level/1}
      ],
      Tesla.Adapter.Finch,
      name: TeslaMate.HTTP,
      receive_timeout: 35_000
    )
  end

  defp log_level(%Tesla.Env{} = env) when env.status >= 500, do: :warning
  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :info
  defp log_level(%Tesla.Env{}), do: :debug
end
