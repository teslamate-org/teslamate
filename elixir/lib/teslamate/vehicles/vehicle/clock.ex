defmodule TeslaMate.Vehicles.Vehicle.Clock do
  @moduledoc """
  The vehicle's view of time: the current instant, the distance between two
  instants as the state machine measures it, and the length of a fetch
  interval as a timer duration.

  Production runs on real time. The test suite runs on a scaled clock in
  which seconds pass as milliseconds — a property of the clock, not of the
  vehicle — so that environment choice lives here, in `default/0`, and the
  vehicle carries no environment branch for time.
  """

  @callback utc_now() :: DateTime.t()
  @callback diff_seconds(DateTime.t(), DateTime.t()) :: integer()
  @callback fetch_timeout(number(), :seconds | :minutes) :: non_neg_integer()

  case Mix.env() do
    :test -> @default __MODULE__.Scaled
    _ -> @default __MODULE__.Real
  end

  def default, do: @default

  defmodule Real do
    @moduledoc "Real time: seconds are seconds."
    @behaviour TeslaMate.Vehicles.Vehicle.Clock

    @impl true
    def utc_now, do: DateTime.utc_now()

    @impl true
    def diff_seconds(a, b), do: DateTime.diff(a, b, :second)

    @impl true
    def fetch_timeout(n, unit), do: round(apply(:timer, unit, [n]))
  end

  defmodule Scaled do
    @moduledoc "Test clock: seconds pass as milliseconds, intervals collapse to their numeric value in milliseconds."
    @behaviour TeslaMate.Vehicles.Vehicle.Clock

    @impl true
    def utc_now, do: DateTime.utc_now()

    @impl true
    def diff_seconds(a, b), do: DateTime.diff(a, b, :millisecond)

    @impl true
    def fetch_timeout(n, _unit), do: round(n)
  end
end
