defmodule TeslaMate.ReleaseTest do
  use ExUnit.Case, async: false

  alias TeslaMate.{Release, Repo}

  @moduletag :capture_log

  @retry_interval 10
  @socket_port 5432

  # while the pool cannot connect, it drops a probe after milliseconds instead
  # of seconds
  @unconnected_probe_drop [queue_target: 5, queue_interval: 10]

  @waiting "Waiting for the database to accept connections"
  @accepting "The database accepts connections"

  # Sends every log event to the test process: errors logged with their reason,
  # as the pool does for failed connection attempts, arrive as the exception.
  defmodule LogForwarder do
    def log(%{msg: msg, meta: meta}, %{config: %{pid: pid}}) do
      case meta do
        %{crash_reason: {error, _stacktrace}} -> send(pid, {:logged_error, error})
        _ -> send(pid, {:log, message(msg)})
      end
    end

    defp message({:string, chardata}), do: IO.chardata_to_string(chardata)
    defp message({:report, report}), do: inspect(report)
    defp message({format, args}), do: format |> :io_lib.format(args) |> IO.chardata_to_string()
  end

  # The server ends the session during the first probe, e.g. while shutting down.
  defmodule SessionEndingRepo do
    def query(_sql, _params, _opts) do
      case Process.put(__MODULE__, :ended) do
        nil -> {:error, error("FATAL", "57P01", "terminating connection")}
        :ended -> {:ok, %Postgrex.Result{}}
      end
    end

    def error(severity, code, message) do
      Postgrex.Error.exception(postgres: %{severity: severity, code: code, message: message})
    end
  end

  defmodule DenyingRepo do
    def query(_sql, _params, _opts) do
      {:error, SessionEndingRepo.error("ERROR", "42501", "permission denied")}
    end
  end

  describe "wait_for_database/2" do
    setup do
      socket_dir = Path.join(System.tmp_dir!(), "teslamate-#{System.unique_integer([:positive])}")
      File.mkdir_p!(socket_dir)

      # the test config logs warnings and up only
      Logger.put_module_level(Release, :info)
      :ok = :logger.add_handler(LogForwarder, LogForwarder, %{config: %{pid: self()}})

      :ok =
        :telemetry.attach(
          __MODULE__,
          [:db_connection, :connection_error],
          &__MODULE__.forward_dropped_probe/4,
          self()
        )

      on_exit(fn ->
        :telemetry.detach(__MODULE__)
        :logger.remove_handler(LogForwarder)
        Logger.delete_module_level(Release)
        File.rm_rf!(socket_dir)
      end)

      %{socket_dir: socket_dir}
    end

    test "returns without logging when the database accepts connections",
         %{socket_dir: socket_dir} do
      start_proxy(socket_dir)
      repo = start_repo(socket_dir: socket_dir)
      assert_receive {:connected, _connection}

      assert :ok = wait_for_database(repo)

      refute_received {:log, @waiting}
    end

    test "waits while the socket is missing and returns once the database accepts connections",
         %{socket_dir: socket_dir} do
      repo = start_repo([socket_dir: socket_dir] ++ @unconnected_probe_drop)
      task = Task.async(fn -> wait_for_database(repo) end)

      assert_receive {:logged_error, %DBConnection.ConnectionError{message: reason}}
      assert reason =~ "no such file or directory"
      assert_receive {:log, @waiting}

      start_proxy(socket_dir)

      assert :ok = Task.await(task)
      assert_received {:log, @accepting}

      # the pool would outlive the proxy otherwise and log its reconnects
      stop_supervised!(Repo)
    end

    test "keeps waiting while the database rejects the connection, logging the reason",
         %{socket_dir: socket_dir} do
      start_proxy(socket_dir)

      repo =
        start_repo(
          [socket_dir: socket_dir, database: "teslamate_missing"] ++ @unconnected_probe_drop
        )

      task = Task.async(fn -> wait_for_database(repo) end)

      assert_receive {:logged_error, %Postgrex.Error{postgres: %{code: :invalid_catalog_name}}}

      # the task reports the first dropped probe before it logs the wait, so
      # the next one proves a probe after the wait began
      assert_receive :probe_dropped
      assert_receive {:log, @waiting}
      assert_receive :probe_dropped

      assert Task.shutdown(task, :brutal_kill) == nil
      refute_received {:log, @accepting}
    end

    test "waits while the server ends the session" do
      assert :ok = Release.wait_for_database(SessionEndingRepo, @retry_interval)

      assert_received {:log, @waiting}
      assert_received {:log, @accepting}
    end

    test "raises any other error" do
      assert_raise Postgrex.Error, ~r/permission denied/, fn ->
        Release.wait_for_database(DenyingRepo, @retry_interval)
      end

      refute_received {:log, @waiting}
    end
  end

  def forward_dropped_probe(_event, _measurements, _metadata, pid) do
    send(pid, :probe_dropped)
  end

  defp wait_for_database(repo) do
    Repo.put_dynamic_repo(repo)
    Release.wait_for_database(Repo, @retry_interval)
  end

  defp start_repo(opts) do
    opts =
      Keyword.merge(
        [
          name: nil,
          pool: DBConnection.ConnectionPool,
          pool_size: 1,
          port: @socket_port,
          backoff_min: 10,
          backoff_max: 50,
          connection_listeners: [self()]
        ],
        opts
      )

    start_supervised!({Repo, opts})
  end

  # Serves the socket in `socket_dir` by forwarding every connection to the
  # test database, wherever that listens.
  defp start_proxy(socket_dir) do
    path = Path.join(socket_dir, ".s.PGSQL.#{@socket_port}")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, ifaddr: {:local, path}, active: false])

    proxy = start_supervised!({Task, fn -> accept(listener) end}, id: :proxy)

    # the listener closes with its owner, which has to be the proxy, not the test
    :ok = :gen_tcp.controlling_process(listener, proxy)
  end

  defp accept(listener) do
    {:ok, client} = :gen_tcp.accept(listener)
    spawn_link(fn -> proxy(client) end)
    accept(listener)
  end

  # Runs in its own process, which owns the connection to the database.
  defp proxy(client) do
    {address, port, opts} = database_address()
    {:ok, database} = :gen_tcp.connect(address, port, [:binary, active: false] ++ opts)

    spawn_link(fn -> forward(database, client) end)
    forward(client, database)
  end

  defp forward(from, to) do
    with {:ok, data} <- :gen_tcp.recv(from, 0),
         :ok <- :gen_tcp.send(to, data) do
      forward(from, to)
    else
      {:error, _reason} -> :gen_tcp.close(to)
    end
  end

  defp database_address do
    config = Repo.config()
    port = config |> Keyword.get(:port, 5432) |> to_string() |> String.to_integer()

    case config[:socket_dir] do
      nil -> {String.to_charlist(config[:hostname]), port, config[:socket_options] || []}
      dir -> {{:local, "#{dir}/.s.PGSQL.#{port}"}, 0, []}
    end
  end
end
