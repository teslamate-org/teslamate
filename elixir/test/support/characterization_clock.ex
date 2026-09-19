defmodule TeslaMate.Characterization.Clock do
  @moduledoc """
  The replay's clock: scenario time instead of wall-clock time.

  Real in distance, scaled in interval — `diff_seconds/2` measures real
  seconds of scenario time (three idle minutes are three minutes of payload
  time), `fetch_timeout/2` collapses intervals to milliseconds like
  `Vehicle.Clock.Scaled` so polls stay fast. `utc_now/0` strictly
  increases with every API serve — at least one millisecond, or the
  payload's own time when that lies further ahead — advanced at the serve
  boundary before the vehicle processes the payload; an explicit
  `{"clock": <epoch ms>}` event sets it forward. One replay runs at a time, so one ETS entry holds it.
  """

  @behaviour TeslaMate.Vehicles.Vehicle.Clock

  @table :characterization_clock
  # Scenarios without any payload timestamp (asleep/offline only) start here.
  @epoch 1_704_067_200_000

  def epoch, do: @epoch

  @doc "Starts a replay's clock at the scenario's smallest payload time."
  def reset(initial_ms) when is_integer(initial_ms) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ets.insert(@table, {:now, initial_ms})
    :ok
  end

  @doc "Advances to a payload time; older payloads never move the clock back."
  def advance(ms) when is_integer(ms) do
    :ets.insert(@table, {:now, max(now_ms(), ms)})
    :ok
  end

  @doc """
  Every API serve is a new instant: the clock strictly increases by at least
  one millisecond per serve, and jumps to the payload's time when that lies
  further ahead. A serve without a payload time (asleep, offline, errors)
  still ticks — in production time always passes between two fetches, and
  a state row that starts and ends at the same instant would swallow a
  `since` transition.
  """
  def serve(payload_ms) when is_integer(payload_ms) or is_nil(payload_ms) do
    :ets.insert(@table, {:now, max(now_ms() + 1, payload_ms || 0)})
    :ok
  end

  @doc "Sets the clock from an explicit clock event; a backward step raises."
  def set!(ms) when is_integer(ms) do
    now = now_ms()

    if ms < now do
      raise "clock event #{ms} lies before the replay's current time #{now} — " <>
              "the clock only moves forward"
    end

    :ets.insert(@table, {:now, ms})
    :ok
  end

  def now_ms do
    [{:now, ms}] = :ets.lookup(@table, :now)
    ms
  end

  @impl true
  def utc_now, do: DateTime.from_unix!(now_ms(), :millisecond)

  @impl true
  def diff_seconds(a, b), do: DateTime.diff(a, b, :second)

  @impl true
  def fetch_timeout(n, _unit), do: round(n)
end
