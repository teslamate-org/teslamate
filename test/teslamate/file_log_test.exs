defmodule TeslaMate.FileLogTest do
  use ExUnit.Case

  require Logger

  alias TeslaMate.FileLog

  @handler_id :teslamate_file_log_test

  setup do
    directory =
      Path.join(System.tmp_dir!(), "teslamate-file-log-#{System.unique_integer([:positive])}")

    path = Path.join(directory, "teslamate.log")

    on_exit(fn ->
      :logger.remove_handler(@handler_id)
      File.rm_rf(directory)
    end)

    %{path: path}
  end

  test "installs the rotating handler and redacts before writing", %{path: path} do
    config = config(path, max_bytes: 1_000, max_files: 2)

    assert :ok = FileLog.install(config: config, handler_id: @handler_id)
    assert :ok = FileLog.install(config: config, handler_id: @handler_id)

    Logger.error("Authorization: Bearer file-secret")
    assert :ok = :logger_std_h.filesync(@handler_id)

    assert {:ok, handler_config} = :logger.get_handler_config(@handler_id)
    assert handler_config.config.max_no_bytes == 1_000
    assert handler_config.config.max_no_files == 2
    assert handler_config.config.compress_on_rotate

    assert FileLog.status(config: config, handler_id: @handler_id) == %{
             enabled?: true,
             active?: true,
             readable?: true,
             size_bytes: File.stat!(path).size
           }

    content = File.read!(path)
    assert content =~ "Authorization: [REDACTED]"
    refute content =~ "file-secret"
  end

  test "reads only a bounded redacted tail", %{path: path} do
    lines =
      for number <- 1..40 do
        "line #{number} token=secret-#{number}"
      end

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Enum.join(lines, "\n") <> "\n")

    assert {:ok, tail} =
             FileLog.tail(config: config(path), tail_bytes: 220, tail_lines: 4)

    assert tail.truncated?
    assert length(tail.lines) == 4
    assert List.last(tail.lines) =~ "line 40"
    assert Enum.all?(tail.lines, &(&1 =~ "token=[REDACTED]"))
    refute Enum.any?(tail.lines, &(&1 =~ "secret-"))
    assert tail.bytes_read <= 220
    assert tail.file_size_bytes == File.stat!(path).size
  end

  test "discards a partial UTF-8 line at the byte boundary", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, String.duplicate("á", 30) <> "\ncomplete token=secret\n")

    assert {:ok, tail} = FileLog.tail(config: config(path), tail_bytes: 30, tail_lines: 5)
    assert tail.lines == ["complete token=[REDACTED]"]
    assert tail.truncated?
  end

  test "reports disabled and missing log files without exposing a path", %{path: path} do
    assert {:error, :disabled} = FileLog.tail(config: config(path, enabled: false))
    assert {:error, :not_found} = FileLog.tail(config: config(path))

    assert FileLog.status(config: config(path, enabled: false)) == %{
             enabled?: false,
             active?: false,
             readable?: false,
             size_bytes: nil
           }

    assert FileLog.status(config: config(path)) == %{
             enabled?: true,
             active?: false,
             readable?: false,
             size_bytes: 0
           }
  end

  test "rejects invalid limits without reading", %{path: path} do
    assert {:error, :invalid_configuration} =
             FileLog.tail(config: config(path), tail_lines: 0)
  end

  defp config(path, overrides \\ []) do
    Keyword.merge(
      [
        enabled: true,
        path: path,
        max_bytes: 5_000_000,
        max_files: 3,
        filesync_interval: 10_000
      ],
      overrides
    )
  end
end
