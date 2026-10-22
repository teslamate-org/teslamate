defmodule TeslaMate.Import.RejectionReport do
  @moduledoc false

  alias TeslaMate.Import.RejectedRow

  @max_examples 100

  defstruct count: 0, examples: []

  def max_examples, do: @max_examples

  def record(%__MODULE__{} = report, %RejectedRow{} = rejected_row) do
    examples =
      if length(report.examples) < @max_examples do
        report.examples ++ [rejected_row]
      else
        report.examples
      end

    %__MODULE__{report | count: report.count + 1, examples: examples}
  end

  def truncated?(%__MODULE__{count: count, examples: examples}), do: count > length(examples)
end
