defmodule TeslaApi.Error do
  @enforce_keys [:reason]
  defstruct [:reason, :message, :env]
end
