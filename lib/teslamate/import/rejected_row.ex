defmodule TeslaMate.Import.RejectedRow do
  @moduledoc false

  @max_fields 8

  @enforce_keys [:file, :row, :reason]
  defstruct [:file, :file_fingerprint, :row, :reason, fields: []]

  def new(path, row, reason, fields \\ [], file_fingerprint \\ nil) do
    %__MODULE__{
      file: Path.basename(path),
      file_fingerprint: file_fingerprint,
      row: row,
      reason: reason,
      fields:
        fields
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.take(@max_fields)
    }
  end
end

defmodule TeslaMate.Import.RejectionReport do
  @moduledoc false

  alias TeslaMate.Import.RejectedRow

  @max_examples 100

  defstruct count: 0, examples: []

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
