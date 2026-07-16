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
          |> Stream.flat_map(fn
            [""] ->
              []

            row when length(row) == column_count ->
              [{:ok, headers |> Enum.zip(row) |> Enum.into(%{})}]

            _row ->
              [{:error, :column_count_mismatch, ["columns"]}]
          end)

        {:ok, rows}
    end
  end
end
