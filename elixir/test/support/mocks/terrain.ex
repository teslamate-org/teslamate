defmodule TerrainMock do
  # The terrain without data, except the answers a characterization replay
  # declares at exact coordinates (TeslaMate.Characterization): an elevation
  # or a lookup that cannot answer.

  def declare(rows) do
    answers = Map.new(rows, fn {{lat, lng}, answer} -> {{lat / 1, lng / 1}, answer} end)
    :persistent_term.put(__MODULE__, answers)
  end

  def get_elevation({lat, lng}) do
    __MODULE__
    |> :persistent_term.get(%{})
    |> Map.get({lat / 1, lng / 1}, {:ok, nil})
  end
end
