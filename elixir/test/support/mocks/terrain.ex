defmodule TerrainMock do
  # The terrain without data, except the elevations a characterization
  # replay declares at exact coordinates (TeslaMate.Characterization).

  def declare(rows) do
    elevations = Map.new(rows, fn {{lat, lng}, elevation} -> {{lat / 1, lng / 1}, elevation} end)
    :persistent_term.put(__MODULE__, elevations)
  end

  def get_elevation({lat, lng}) do
    __MODULE__
    |> :persistent_term.get(%{})
    |> Map.get({lat / 1, lng / 1})
  end
end
