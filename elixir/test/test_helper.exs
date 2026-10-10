# ElixirLS Test Explorer starts the full app (it cannot pass --no-start).
# Tear it down so tests get the same Repo + PubSub tree as `mix test`.
case Application.stop(:teslamate) do
  :ok -> :ok
  {:error, {:not_started, :teslamate}} -> :ok
end

# `mix test --no-start` only loads config; Mix restarts Logger when it starts
# the app. Bounce it here so config/test.exs (level: :warning) takes effect.
Application.stop(:logger)
Application.start(:logger)

Application.load(:teslamate)

for app <- Application.spec(:teslamate, :applications) do
  {:ok, _} = Application.ensure_all_started(app)
end

{:ok, _} = TeslaMate.Repo.start_link()
# The sandbox rolls back rows, not sequences: `cars_id_seq` grows across runs
# until it exceeds `cars.id` (smallint). `cars` is empty between runs, so restart at 1.
Ecto.Adapters.SQL.query!(TeslaMate.Repo, "ALTER SEQUENCE cars_id_seq RESTART WITH 1")
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: TeslaMate.PubSub)

assert_timeout = String.to_integer(System.get_env("ELIXIR_ASSERT_TIMEOUT") || "300")
ExUnit.start(assert_receive_timeout: assert_timeout)
