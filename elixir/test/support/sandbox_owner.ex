defmodule TeslaMate.SandboxOwner do
  @moduledoc """
  Starts the SQL sandbox owner for a test and waits out the asynchronous
  release of the previous test's shared owner instead of silently riding it.

  The case templates used to rescue `:already_shared` into `:ok`, leaving the
  test without an owner of its own on the previous test's shared connection:
  the test then read the previous test's uncommitted data — or lost its
  connection mid-test when that owner finished dying. Both surfaced as
  intermittent characterization failures; in record mode the same channel
  could capture foreign rows into a golden. Waiting synchronizes on the real
  release event; a release that never comes raises instead of sharing.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @attempts 50
  @delay_ms 10
  @key :teslamate_sandbox_owner

  # Several test modules use two case templates (e.g. ConnCase + VehicleCase),
  # so both setups call this in the same test process: the second call is a
  # no-op — that benign duplication is what the old rescue actually covered.
  def start!(tags) do
    if Process.get(@key) do
      :ok
    else
      start!(tags, @attempts)
    end
  end

  defp start!(tags, attempts) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TeslaMate.Repo, shared: not tags[:async])
    Process.put(@key, pid)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  rescue
    e in [MatchError] ->
      case e.term do
        {:error, {{:badmatch, :already_shared}, _}} when attempts > 1 ->
          Process.sleep(@delay_ms)
          start!(tags, attempts - 1)

        {:error, {{:badmatch, :already_shared}, _}} ->
          raise "the previous test's shared sandbox owner did not release within " <>
                  "#{@attempts * @delay_ms}ms — refusing to run on a foreign owner"

        _ ->
          reraise e, __STACKTRACE__
      end
  end
end
