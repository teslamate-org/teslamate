defmodule TeslaMate.Import.CSV do
  NimbleCSV.define(Parser, separator: ",", escape: "\"", newlines: ["\r\n", "\n"])

  def parse(file_stream) do
    file_stream
    |> Parser.parse_stream(skip_headers: false)
    |> Enum.take(2)
    |> case do
      [[_], _] ->
        {:error, :unsupported_delimiter}

      [] ->
        {:error, :no_contents}

      [_] ->
        {:error, :no_contents}

      [headers, _] ->
        column_count = length(headers)

        rows =
          file_stream
          |> Parser.parse_stream()
          |> Stream.with_index(2)
          |> Stream.flat_map(fn
            {[""], _row_number} ->
              []

            {row, row_number} when length(row) == column_count ->
              [{:ok, row_number, headers |> Enum.zip(row) |> Enum.into(%{})}]

            {_row, row_number} ->
              [{:error, row_number, :column_count_mismatch, ["columns"]}]
          end)

        {:ok, rows}
    end
  end
end
