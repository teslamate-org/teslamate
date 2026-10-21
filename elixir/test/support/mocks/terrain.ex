defmodule TerrainMock do
  # The terrain without data, except the answers a characterization replay
  # declares at exact coordinates (TeslaMate.Characterization): an elevation,
  # possibly only after a number of lookups that cannot answer.

  def declare(rows) do
    answers =
      Map.new(rows, fn
        {{lat, lng}, {:after_unavailable, n, answer}} ->
          failed = :counters.new(1, [])
          {{lat / 1, lng / 1}, {:after_unavailable, n, failed, answer}}

        {{lat, lng}, answer} ->
          {{lat / 1, lng / 1}, answer}
      end)

    :persistent_term.put(__MODULE__, answers)
  end

  def get_elevation({lat, lng}) do
    case Map.get(:persistent_term.get(__MODULE__, %{}), {lat / 1, lng / 1}, {:ok, nil}) do
      {:after_unavailable, n, failed, answer} ->
        if :counters.get(failed, 1) < n do
          :counters.add(failed, 1, 1)
          {:error, :unavailable}
        else
          answer
        end

      answer ->
        answer
    end
  end
end
