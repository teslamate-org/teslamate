defmodule TeslaApi do
  @version Mix.Project.config()[:version]
  @sensitive_headers ~w(Authorization authorization)

  def client do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "https://owner-api.teslamotors.com"},
        {Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]},
        Tesla.Middleware.JSON,
        TeslaApi.Middleware.TokenAuth,
        TeslaApi.Middleware.FleetAuth,
        {Tesla.Middleware.Logger,
         debug: true,
         filter_headers: @sensitive_headers,
         format: &__MODULE__.format_log/3,
         level: &log_level/1}
      ],
      {Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 35_000}
    )
  end

  # Request opts (`query:`, `opts: [access_token: ...]`) must be forwarded:
  # TokenAuth reads the token from `env.opts`.
  def get(url, opts \\ []) do
    Tesla.get(client(), url, opts)
  end

  def format_log(%Tesla.Env{} = request, response, time) do
    [
      request.method |> to_string() |> String.upcase(),
      " ",
      TeslaApi.Error.redact_url(request.url),
      " -> ",
      response_status(response),
      " (",
      :io_lib.format("~.3f", [time / 1000]),
      " ms)"
    ]
  end

  defp log_level({:ok, %Tesla.Env{} = env}) when env.status >= 500, do: :warning
  defp log_level({:ok, %Tesla.Env{} = env}) when env.status >= 400, do: :info
  defp log_level({:ok, %Tesla.Env{}}), do: :debug
  defp log_level({:error, _reason}), do: :error

  defp response_status({:ok, %Tesla.Env{} = env}), do: to_string(env.status)
  defp response_status({:error, reason}), do: "error: " <> inspect(reason)
end
