defmodule TeslaMate.BuildInfo do
  @moduledoc """
  Returns validated identity for the running TeslaMate build.

  Build metadata is supplied by image builders. Missing or malformed values are
  omitted so local and source builds continue to report only the application
  version.
  """

  @revision_regex ~r/\A[0-9a-fA-F]{7,64}\z/
  @source_regex ~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/

  @type t :: %{
          version: String.t(),
          revision: String.t() | nil,
          ref: String.t() | nil,
          source: String.t() | nil,
          built_at: String.t() | nil
        }

  @spec current(keyword()) :: t()
  def current(opts \\ []) do
    config = Keyword.get(opts, :config, Application.get_env(:teslamate, :build_info, []))

    %{
      version:
        opts
        |> Keyword.get(:version, Application.spec(:teslamate, :vsn) || "unknown")
        |> to_string()
        |> clean_text(64)
        |> fallback("unknown"),
      revision: config |> get_value(:revision) |> clean_revision(),
      ref: config |> get_value(:ref) |> clean_text(255),
      source: config |> get_value(:source) |> clean_source(),
      built_at: config |> get_value(:built_at) |> clean_datetime()
    }
  end

  @spec metadata?(t()) :: boolean()
  def metadata?(build_info) do
    Enum.any?([build_info.revision, build_info.ref, build_info.source, build_info.built_at])
  end

  @spec log_line(t()) :: String.t()
  def log_line(build_info \\ current()) do
    details =
      [
        source: build_info.source,
        ref: build_info.ref,
        revision: build_info.revision,
        built_at: build_info.built_at
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{value}" end)

    if details == "", do: "Version: #{build_info.version}", else: "Build: #{details}"
  end

  defp get_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp get_value(config, key) when is_map(config), do: Map.get(config, key)
  defp get_value(_config, _key), do: nil

  defp clean_revision(value) do
    case clean_text(value, 64) do
      revision when is_binary(revision) ->
        if Regex.match?(@revision_regex, revision), do: String.downcase(revision)

      nil ->
        nil
    end
  end

  defp clean_source(value) do
    case clean_text(value, 200) do
      source when is_binary(source) ->
        if Regex.match?(@source_regex, source), do: source

      nil ->
        nil
    end
  end

  defp clean_datetime(value) do
    with datetime when is_binary(datetime) <- clean_text(value, 64),
         {:ok, parsed, _offset} <- DateTime.from_iso8601(datetime) do
      DateTime.to_iso8601(parsed)
    else
      _ -> nil
    end
  end

  defp clean_text(value, max_length) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= max_length and String.printable?(value) and
         not String.contains?(value, ["\n", "\r"]) do
      value
    end
  end

  defp clean_text(_value, _max_length), do: nil

  defp fallback(nil, default), do: default
  defp fallback(value, _default), do: value
end
