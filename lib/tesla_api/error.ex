defmodule TeslaApi.Error do
  defexception [:reason, :message, :env]

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

    {:error, %__MODULE__{reason: reason, message: message, env: env}}
  end

  def into({:error, reason}, _reason) when is_atom(reason) do
    {:error, %__MODULE__{reason: reason}}
  end

  def into({:error, error}, reason) do
    {:error, %__MODULE__{reason: reason, message: error}}
  end
end
