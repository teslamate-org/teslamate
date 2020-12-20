defmodule TeslaApi.Error do
  defexception [:reason, :message, :env]

  @impl true
  def message(%__MODULE__{message: message}) when is_binary(message), do: message
  def message(%__MODULE__{reason: reason}), do: inspect(reason)
end
