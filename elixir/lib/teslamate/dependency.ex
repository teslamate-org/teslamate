defmodule Core.Dependency do
  def call(m, f, a \\ [])
  def call({m, a}, fun, args), do: apply(m, fun, [a] ++ args)
  def call(m, f, a), do: apply(m, f, a)
end
