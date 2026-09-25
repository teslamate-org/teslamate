defmodule TeslaApi.Error do
  defexception [:reason, :message, :env]

  @redacted "[redacted]"
  @sensitive_keys ~w(access_token refresh_token token authorization)
  @sensitive_headers ~w(authorization)

  @impl true
  def message(%__MODULE__{message: message}) when is_binary(message), do: message
  def message(%__MODULE__{reason: e}) when is_exception(e), do: Exception.message(e)
  def message(%__MODULE__{reason: reason}), do: inspect(reason)

  def into(response, reason \\ :unknown)

  def into({:ok, %Tesla.Env{} = env}, reason) do
    message =
      case env.body do
        %{"error" => %{"message" => message}} when is_binary(message) ->
          message

        body when is_binary(body) ->
          case Floki.parse_document(body) do
            {:error, _} -> body
            {:ok, _} -> nil
          end

        _ ->
          nil
      end

    {:error, %__MODULE__{reason: reason, message: message, env: redact_env(env)}}
  end

  def into({:error, reason}, _reason) when is_atom(reason) do
    {:error, %__MODULE__{reason: reason}}
  end

  def into({:error, error}, reason) do
    {:error, %__MODULE__{reason: reason, message: error}}
  end

  def redacted(%__MODULE__{} = error) do
    %__MODULE__{error | env: redact_env(error.env)}
  end

  defp redact_env(%Tesla.Env{} = env) do
    %Tesla.Env{
      env
      | url: redact_url(env.url),
        query: redact_pairs(env.query),
        headers: redact_headers(env.headers),
        opts: redact_pairs(env.opts)
    }
  end

  defp redact_env(env), do: env

  defp redact_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) ->
        if sensitive_header?(key), do: {key, @redacted}, else: {key, value}

      other ->
        other
    end)
  end

  defp redact_headers(headers), do: headers

  @doc """
  Redacts the credentials a URL can carry: its userinfo and its sensitive
  query parameters.
  """
  def redact_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{userinfo: nil, query: nil} ->
        url

      uri ->
        URI.to_string(%URI{
          uri
          | userinfo: redact_userinfo(uri.userinfo),
            query: redact_query(uri.query)
        })
    end
  rescue
    _ -> url
  end

  def redact_url(url), do: url

  defp redact_userinfo(nil), do: nil
  defp redact_userinfo(_userinfo), do: @redacted

  defp redact_query(nil), do: nil

  defp redact_query(query) do
    query
    |> URI.decode_query()
    |> Map.new(fn {key, value} ->
      if sensitive_key?(key), do: {key, @redacted}, else: {key, value}
    end)
    |> URI.encode_query()
  end

  defp redact_pairs(values) when is_list(values) do
    Enum.map(values, fn
      {key, value} when is_atom(key) or is_binary(key) ->
        if sensitive_key?(key), do: {key, @redacted}, else: {key, value}

      value ->
        value
    end)
  end

  defp redact_pairs(values), do: values

  defp sensitive_key?(key) when is_atom(key), do: key |> Atom.to_string() |> sensitive_key?()

  defp sensitive_key?(key) when is_binary(key),
    do: key |> String.downcase() |> then(&(&1 in @sensitive_keys))

  defp sensitive_key?(_key), do: false

  defp sensitive_header?(key) do
    key
    |> String.downcase()
    |> then(&(&1 in @sensitive_headers))
  end
end

defimpl Inspect, for: TeslaApi.Error do
  def inspect(error, opts) do
    error = TeslaApi.Error.redacted(error)
    fields = [%{field: :reason}, %{field: :message}, %{field: :env}]

    error
    |> Map.from_struct()
    |> Inspect.Map.inspect_as_struct("TeslaApi.Error", fields, opts)
  end
end
