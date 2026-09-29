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

  defp await_database(repo, retry_interval) do
    Process.sleep(retry_interval)

    case ping(repo) do
      :ok -> :ok
      :unavailable -> await_database(repo, retry_interval)
    end
  end

  defp ping(repo) do
    case repo.query("SELECT 1", [], log: false) do
      {:ok, _result} ->
        :ok

      {:error, %DBConnection.ConnectionError{}} ->
        :unavailable

      # the server ended the session, e.g. while shutting down
      {:error, %Postgrex.Error{postgres: %{severity: severity}}}
      when severity in ["FATAL", "PANIC"] ->
        :unavailable

      {:error, error} ->
        raise error
    end
  end

  defp repos do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
