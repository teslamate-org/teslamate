defmodule TeslaApi.Error do
  defexception [:reason, :message, :env]

  @impl true
  def message(%__MODULE__{message: message}) when is_binary(message), do: message
  def message(%__MODULE__{reason: e}) when is_exception(e), do: Exception.message(e)
  def message(%__MODULE__{reason: reason}), do: inspect(reason)
end
