defmodule TestHelper do
  def eventually(fun, opts \\ []) do
    eventually(fun, Keyword.get(opts, :attempts, 10), Keyword.get(opts, :delay, 100))
  end

  defp eventually(fun, attempts, delay) do
    fun.()
  rescue
    e in [ExUnit.AssertionError] ->
      if attempts == 1, do: reraise(e, __STACKTRACE__)
      Process.sleep(delay)
      eventually(fun, attempts - 1, delay)
  end

  defmacro decimal(value) do
    value
    |> to_string()
    |> Decimal.new()
    |> Macro.escape()
  end
end
