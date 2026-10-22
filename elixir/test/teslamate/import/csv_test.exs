defmodule TeslaMate.Import.CSVTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Import.CSV

  test "marks short and long rows as column-count errors" do
    csv = ["a,b\n", "1,2\n", "3\n", "4,5,6\n"]

    assert {:ok, rows} = CSV.parse(csv)

    assert [
             {:ok, 2, %{"a" => "1", "b" => "2"}},
             {:error, 3, :column_count_mismatch, ["columns"]},
             {:error, 4, :column_count_mismatch, ["columns"]}
           ] = Enum.to_list(rows)
  end

  test "preserves source row numbers after blank lines" do
    csv = ["a,b\n", "1,2\n", "\n", "3\n"]

    assert {:ok, rows} = CSV.parse(csv)

    assert [
             {:ok, 2, %{"a" => "1", "b" => "2"}},
             {:error, 4, :column_count_mismatch, ["columns"]}
           ] = Enum.to_list(rows)
  end
end
