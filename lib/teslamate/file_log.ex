defmodule TeslaMate.FileLog.Formatter do
  @moduledoc false

  @behaviour :logger_formatter

  alias TeslaMate.LogRedactor

  def new do
    delegate =
      Logger.Formatter.new(
        format: "$date $time $metadata[$level] $message\n",
        metadata: [:car_id],
        colors: [enabled: false],
        utc_log: true
      )

    {__MODULE__, %{delegate: delegate}}
  end

  @impl true
  def check_config(%{delegate: {module, config}}) when is_atom(module) and is_map(config), do: :ok

  def check_config(config), do: {:error, {:invalid_formatter_config, __MODULE__, config}}

  @impl true
  def format(event, %{delegate: {module, config}}) do
    event
    |> module.format(config)
    |> IO.iodata_to_binary()
    |> LogRedactor.redact()
  rescue
    _error -> "[error] Log event could not be formatted safely\n"
  end
end

defmodule TeslaMate.FileLog do
  @moduledoc """
  Installs a bounded rotating file logger and reads a bounded redacted tail.

  File logging is disabled by default and must be enabled at application start.
  """

  alias TeslaMate.FileLog.Formatter
  alias TeslaMate.LogRedactor

  @handler_id :teslamate_file_log
  @default_max_bytes 5_000_000
  @default_max_files 3
  @default_tail_bytes 256_000
  @default_tail_lines 500

  defmodule Tail do
    @moduledoc "A bounded snapshot of the current log file suffix."

    @enforce_keys [
      :read_at,
      :lines,
      :truncated?,
      :bytes_read,
      :file_size_bytes
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            read_at: DateTime.t(),
            lines: [String.t()],
            truncated?: boolean(),
            bytes_read: non_neg_integer(),
            file_size_bytes: non_neg_integer()
          }
  end

  @spec install(keyword()) :: :ok | :disabled | {:error, atom()}
  def install(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @handler_id)

    with {:ok, config} <- config(opts),
         true <- config.enabled? || :disabled,
         :ok <- File.mkdir_p(Path.dirname(config.path)),
         :ok <- add_handler(handler_id, config) do
      :ok
    else
      :disabled -> :disabled
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    _error -> {:error, :invalid_configuration}
  end

  @spec tail(keyword()) :: {:ok, Tail.t()} | {:error, atom()}
  def tail(opts \\ []) do
    max_bytes = positive_option(opts, :tail_bytes, @default_tail_bytes)
    max_lines = positive_option(opts, :tail_lines, @default_tail_lines)

    with {:ok, config} <- config(opts),
         true <- config.enabled? || :disabled,
         {:ok, stat} <- File.stat(config.path),
         {:ok, data, offset} <- read_suffix(config.path, stat.size, max_bytes) do
      lines = tail_lines(data, offset, max_lines)

      {:ok,
       %Tail{
         read_at: DateTime.utc_now(),
         lines: Enum.map(lines, &LogRedactor.redact/1),
         truncated?: offset > 0 or length(lines) < line_count(data, offset),
         bytes_read: byte_size(data),
         file_size_bytes: stat.size
       }}
    else
      :disabled -> {:error, :disabled}
      {:error, :enoent} -> {:error, :not_found}
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    _error -> {:error, :invalid_configuration}
  end

  @spec status(keyword()) :: map()
  def status(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @handler_id)

    case config(opts) do
      {:ok, %{enabled?: false}} ->
        %{enabled?: false, active?: false, readable?: false, size_bytes: nil}

      {:ok, %{enabled?: true, path: path}} ->
        case File.stat(path) do
          {:ok, stat} ->
            %{
              enabled?: true,
              active?: handler_installed?(handler_id),
              readable?: true,
              size_bytes: stat.size
            }

          {:error, :enoent} ->
            %{
              enabled?: true,
              active?: handler_installed?(handler_id),
              readable?: false,
              size_bytes: 0
            }

          {:error, _reason} ->
            %{
              enabled?: true,
              active?: handler_installed?(handler_id),
              readable?: false,
              size_bytes: nil
            }
        end

      {:error, _reason} ->
        %{enabled?: false, active?: false, readable?: false, size_bytes: nil}
    end
  end

  defp config(opts) do
    source = Keyword.get(opts, :config, Application.get_env(:teslamate, :file_logging, []))

    config = %{
      enabled?: get_value(source, :enabled, false) == true,
      path: get_value(source, :path),
      max_bytes: get_value(source, :max_bytes, @default_max_bytes),
      max_files: get_value(source, :max_files, @default_max_files),
      filesync_interval: get_value(source, :filesync_interval, 10_000)
    }

    if valid_config?(config), do: {:ok, config}, else: {:error, :invalid_configuration}
  end

  defp valid_config?(%{
         path: path,
         max_bytes: max_bytes,
         max_files: max_files,
         filesync_interval: filesync_interval
       }) do
    is_binary(path) and String.trim(path) != "" and is_integer(max_bytes) and max_bytes > 0 and
      is_integer(max_files) and max_files >= 0 and is_integer(filesync_interval) and
      filesync_interval > 0
  end

  defp add_handler(handler_id, config) when is_atom(handler_id) do
    case :logger.get_handler_config(handler_id) do
      {:ok, _handler_config} ->
        :ok

      {:error, {:not_found, ^handler_id}} ->
        handler_config = %{
          config: %{
            file: String.to_charlist(config.path),
            filesync_repeat_interval: config.filesync_interval,
            file_check: 5_000,
            max_no_bytes: config.max_bytes,
            max_no_files: config.max_files,
            compress_on_rotate: true
          },
          filter_default: :log,
          filters: [],
          formatter: Formatter.new(),
          id: handler_id,
          module: :logger_std_h,
          level: :all
        }

        case :logger.add_handler(handler_id, :logger_std_h, handler_config) do
          :ok -> :ok
          {:error, _reason} -> {:error, :handler_unavailable}
        end
    end
  end

  defp add_handler(_handler_id, _config), do: {:error, :invalid_handler_id}

  defp handler_installed?(handler_id) do
    match?({:ok, _handler_config}, :logger.get_handler_config(handler_id))
  end

  defp read_suffix(path, size, max_bytes) do
    bytes_to_read = min(size, max_bytes)
    offset = size - bytes_to_read

    case File.open(path, [:read, :binary, :raw], &read_bytes(&1, offset, bytes_to_read)) do
      {:ok, {:ok, data}} -> {:ok, data, offset}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_bytes(file, offset, bytes_to_read) do
    with {:ok, _position} <- :file.position(file, {:bof, offset}) do
      normalize_read(IO.binread(file, bytes_to_read))
    end
  end

  defp normalize_read(:eof), do: {:ok, <<>>}
  defp normalize_read(data) when is_binary(data), do: {:ok, data}
  defp normalize_read({:error, reason}), do: {:error, reason}

  defp tail_lines(data, offset, max_lines) do
    data
    |> split_lines(offset)
    |> Enum.take(-max_lines)
  end

  defp line_count(data, offset), do: data |> split_lines(offset) |> length()

  defp split_lines(data, offset) do
    data
    |> discard_partial_line(offset)
    |> String.split(~r/\R/, trim: true)
  end

  defp discard_partial_line(data, 0), do: data

  defp discard_partial_line(data, _offset) do
    case :binary.match(data, "\n") do
      {position, 1} -> binary_part(data, position + 1, byte_size(data) - position - 1)
      :nomatch -> <<>>
    end
  end

  defp positive_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      value -> raise ArgumentError, "#{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp get_value(source, key, default \\ nil)
  defp get_value(source, key, default) when is_list(source), do: Keyword.get(source, key, default)
  defp get_value(source, key, default) when is_map(source), do: Map.get(source, key, default)
  defp get_value(_source, _key, default), do: default
end
