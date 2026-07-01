defmodule TeslaApi do
  use Tesla

  @version Mix.Project.config()[:version]
  @redacted "[redacted]"
  @sensitive_headers ~w(Authorization authorization)
  @sensitive_query_params ~w(access_token refresh_token token)

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 35_000

  plug Tesla.Middleware.BaseUrl, "https://owner-api.teslamotors.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]
  plug Tesla.Middleware.JSON
  plug TeslaApi.Middleware.TokenAuth

  plug TeslaApi.Middleware.FleetAuth

  plug Tesla.Middleware.Logger,
    debug: true,
    filter_headers: @sensitive_headers,
    format: &__MODULE__.format_log/3,
    log_level: &log_level/1

  def format_log(%Tesla.Env{} = request, response, time) do
    [
      request.method |> to_string() |> String.upcase(),
      " ",
      redact_url(request.url),
      " -> ",
      response_status(response),
      " (",
      :io_lib.format("~.3f", [time / 1000]),
      " ms)"
    ]
  end

  defp log_level(%Tesla.Env{} = env) when env.status >= 500, do: :warning
  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :info
  defp log_level(%Tesla.Env{}), do: :debug

  defp response_status({:ok, %Tesla.Env{} = env}), do: to_string(env.status)
  defp response_status({:error, reason}), do: "error: " <> inspect(reason)

  defp redact_url(url) when is_binary(url) do
    uri = URI.parse(url)

    case uri.query do
      nil ->
        url

      query ->
        query =
          query
          |> URI.decode_query()
          |> Map.new(fn {key, value} ->
            if sensitive_query_param?(key), do: {key, @redacted}, else: {key, value}
          end)
          |> URI.encode_query()

        URI.to_string(%URI{uri | query: query})
    end
  rescue
    _ -> url
  end

  defp redact_url(url), do: url

  defp sensitive_query_param?(key) when is_binary(key),
    do: key |> String.downcase() |> then(&(&1 in @sensitive_query_params))

  defp sensitive_query_param?(_key), do: false
end
