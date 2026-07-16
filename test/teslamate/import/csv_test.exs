defmodule TeslaMate.Import.CSVTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Import.CSV

  test "marks short and long rows as column-count errors" do
    csv = ["a,b\n", "1,2\n", "3\n", "4,5,6\n"]

    assert {:ok, rows} = CSV.parse(csv)

    assert [
             {:ok, %{"a" => "1", "b" => "2"}},
             {:error, :column_count_mismatch, ["columns"]},
             {:error, :column_count_mismatch, ["columns"]}
           ] = Enum.to_list(rows)
  end
end
