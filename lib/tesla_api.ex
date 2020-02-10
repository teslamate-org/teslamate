defmodule TeslaApi do
  alias Mojito.Response, as: Res
  alias Mojito.Error, as: Err
  alias __MODULE__.Error

  @base_url URI.parse("https://owner-api.teslamotors.com/")
  @user_agent "github.com/adriankumpf/teslamate"
  @timeout 30_000

  def get(path, token, opts \\ []) when is_binary(token) do
    headers = [{"user-agent", @user_agent}, {"Authorization", "Bearer " <> token}]

    case Mojito.get(url(path), headers, timeout: @timeout) do
      {:ok, %Res{} = response} ->
        case decode_body(response) do
          %Res{complete: false} = env ->
            {:error, %Error{reason: :incomplete_response, env: env}}

          %Res{status_code: status, body: %{"response" => res}} when status in 200..299 ->
            transform = Keyword.get(opts, :transform, & &1)
            {:ok, if(is_list(res), do: Enum.map(res, transform), else: transform.(res))}

          %Res{status_code: 401} = env ->
            {:error, %Error{reason: :unauthorized, env: env}}

          %Res{status_code: 404, body: %{"error" => "not_found"}} = env ->
            {:error, %Error{reason: :vehicle_not_found, env: env}}

          %Res{status_code: 405, body: %{"error" => "vehicle is curently in service"}} = env ->
            {:error, %Error{reason: :vehicle_in_service, env: env}}

          %Res{status_code: 408, body: %{"error" => "vehicle unavailable:" <> _}} = env ->
            {:error, %Error{reason: :vehicle_unavailable, env: env}}

          %Res{status_code: 504} = env ->
            {:error, %Error{reason: :timeout, env: env}}

          %Res{status_code: status, body: %{"error" => msg}} = env when status >= 500 ->
            {:error, %Error{reason: :unknown, message: msg, env: env}}

          %Res{body: body} = env ->
            {:error, %Error{reason: :unknown, message: inspect(body), env: env}}
        end

      {:error, %Err{reason: reason, message: msg}} ->
        {:error, %Error{reason: reason, message: msg}}
    end
  end

  def post(path, token, params) when is_map(params) do
    body = Jason.encode!(params)

    headers = [
      {"user-agent", @user_agent},
      {"content-type", "application/json"}
      | if(is_nil(token), do: [], else: [{"Authorization", "Bearer " <> token}])
    ]

    with {:ok, response} <- path |> url() |> Mojito.post(headers, body, timeout: @timeout) do
      {:ok, decode_body(response)}
    end
  end

  ## Private

  defp url(path) do
    @base_url
    |> Map.put(:path, path)
    |> URI.to_string()
  end

  defp decode_body(%Res{body: body} = response) do
    body =
      case Jason.decode(body) do
        {:ok, decoded_body} -> decoded_body
        {:error, _reason} -> body
      end

    Map.put(response, :body, body)
  end
end
