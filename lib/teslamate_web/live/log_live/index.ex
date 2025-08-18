defmodule TeslaMateWeb.LogLive.Index do
  use TeslaMateWeb, :live_view

  @log_file_path System.get_env("TESLAMATE_FILE_LOGGING_PATH") ||
                   Path.join(File.cwd!(), "data/logs/teslamate.log")

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, logs: get_logs())}
  end

  @impl true
  def handle_event("refresh_logs", _params, socket) do
    {:noreply, assign(socket, logs: get_logs())}
  end

  defp get_logs() do
    case File.read(@log_file_path) do
      {:ok, content} ->
        content
        |> String.split(~r/\R/, trim: true)
        |> Enum.reverse()

      {:error, :enoent} ->
        ["Log file not found. It will be created when logs are written."]

      {:error, reason} ->
        ["Error reading log file: #{reason}"]
    end
  end
end
