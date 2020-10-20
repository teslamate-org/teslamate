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
        rows =
          file_stream
          |> Parser.parse_stream()
          |> Stream.flat_map(fn
            [""] -> []
            row -> [headers |> Enum.zip(row) |> Enum.into(%{})]
          end)

        {:ok, rows}
    end
  end
end
