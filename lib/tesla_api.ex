defmodule TeslaApi do
  alias Finch.Response, as: Res
  alias TeslaMate.HTTP
  alias __MODULE__.Error

  @base_url URI.parse("https://owner-api.teslamotors.com/")
  @user_agent "github.com/adriankumpf/teslamate"
  @timeout 30_000

  def get(path, token, opts \\ []) when is_binary(token) do
    headers = [{"user-agent", @user_agent}, {"Authorization", "Bearer " <> token}]

    case HTTP.get(url(path), headers: headers, receive_timeout: @timeout) do
      {:ok, %Res{} = response} ->
        case decode_body(response) do
          %Res{status: status, body: %{"response" => res}} when status in 200..299 ->
            transform = Keyword.get(opts, :transform, & &1)
            {:ok, if(is_list(res), do: Enum.map(res, transform), else: transform.(res))}

          %Res{status: 401} = env ->
            {:error, %Error{reason: :unauthorized, env: env}}

          %Res{status: 404, body: %{"error" => "not_found"}} = env ->
            {:error, %Error{reason: :vehicle_not_found, env: env}}

          %Res{status: 405, body: %{"error" => "vehicle is curently in service"}} = env ->
            {:error, %Error{reason: :vehicle_in_service, env: env}}

          %Res{status: 408, body: %{"error" => "vehicle unavailable:" <> _}} = env ->
            {:error, %Error{reason: :vehicle_unavailable, env: env}}

          %Res{status: 504} = env ->
            {:error, %Error{reason: :timeout, env: env}}

          %Res{status: status, body: %{"error" => msg}} = env when status >= 500 ->
            {:error, %Error{reason: :unknown, message: msg, env: env}}

          %Res{body: body} = env ->
            {:error, %Error{reason: :unknown, message: inspect(body), env: env}}
        end

      {:error, %Mint.TransportError{reason: reason} = transport_error} ->
        {:error, %Error{reason: reason, message: Exception.message(transport_error)}}

      {:error, %Mint.HTTPError{reason: reason} = transport_error} ->
        {:error, %Error{reason: reason, message: Exception.message(transport_error)}}
    end
  end

  def post(path, token, params) when is_map(params) do
    body = Jason.encode!(params)

    headers = [
      {"user-agent", @user_agent},
      {"content-type", "application/json"}
      | if(is_nil(token), do: [], else: [{"Authorization", "Bearer " <> token}])
    ]

    with {:ok, response} <-
           HTTP.post(url(path), body, headers: headers, receive_timeout: @timeout) do
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
