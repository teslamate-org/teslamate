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
