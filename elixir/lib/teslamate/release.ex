defmodule TeslaMate.Release do
  @app :teslamate

  import Ecto.Query
  require Logger
  alias TeslaMate.Repo

  @database_retry_interval :timer.seconds(1)

  def migrate do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &run_migrations/1)
    end
  end

  # Waits without a time limit: a database that is not up yet cannot be told
  # apart from one that never will be.
  def wait_for_database_and_migrate do
    for repo <- repos() do
      reconnect_every(repo, @database_retry_interval)

      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          :ok = wait_for_database(repo)
          run_migrations(repo)
        end)
    end
  end

  # Probes through the repo itself, so the wait covers exactly the connection
  # the migrations use (TCP or socket, SSL, IPv6). The pool retries the
  # connection with backoff and logs the reason of every failed attempt; only
  # a missing or ended connection is waited out, anything else raises. A probe
  # is served as soon as the pool connects; while it cannot, the pool drops
  # the probe after its queue interval.
  def wait_for_database(repo, retry_interval \\ @database_retry_interval) do
    case ping(repo) do
      :ok ->
        :ok

      :unavailable ->
        Logger.info("Waiting for the database to accept connections")
        await_database(repo, retry_interval)
        Logger.info("The database accepts connections")
    end
  end

  def rollback(repo, version) do
    for r <- repos(), r == repo do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  end

  def seconds_since_last_migration do
    Repo.one(
      from m in "schema_migrations",
        select: fragment("EXTRACT(EPOCH FROM age(NOW(), ?::timestamp))::BIGINT", m.inserted_at),
        order_by: [desc: m.inserted_at],
        limit: 1
    )
  end

  defp run_migrations(repo) do
    Ecto.Migrator.run(repo, :up, all: true)
  end

  # The migrator starts the pool with nothing but a pool size, so the pool's
  # reconnect backoff comes from the repo config of this VM. The default
  # backoff grows to 30 s; reconnecting at the probe's interval instead
  # notices a database within an interval of it coming up, and brings up the
  # second connection the migrator needs besides the one holding its lock
  # before the pool drops the waiting checkout, after one to two queue
  # intervals.
  defp reconnect_every(repo, interval) do
    config = Application.get_env(@app, repo, [])
    backoff = [backoff_type: :rand, backoff_min: interval, backoff_max: interval]
    Application.put_env(@app, repo, Keyword.merge(config, backoff))
  end

  defp await_database(repo, retry_interval) do
    Process.sleep(retry_interval)

    case ping(repo) do
      :ok -> :ok
      :unavailable -> await_database(repo, retry_interval)
    end
  end

  defp ping(repo) do
    case repo.query("SELECT 1", [], log: false) do
      {:ok, _result} -> :ok
      {:error, error} -> if unavailable?(error), do: :unavailable, else: raise(error)
    end
  end

  defp unavailable?(%DBConnection.ConnectionError{}), do: true

  # the server ended the session, e.g. while shutting down
  defp unavailable?(%Postgrex.Error{postgres: %{severity: severity}}),
    do: severity in ["FATAL", "PANIC"]

  defp unavailable?(_error), do: false

  defp repos do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
