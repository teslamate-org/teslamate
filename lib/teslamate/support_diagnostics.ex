defmodule TeslaMate.SupportDiagnostics do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.{Car, Charge, ChargingProcess, Drive, Position, State, Update}
  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.{Import, Repo, Settings}

  @schema_version 1

  def build do
    %{
      "schemaVersion" => @schema_version,
      "generatedAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "redaction" => redaction_payload(),
      "app" => app_payload(),
      "runtime" => runtime_payload(),
      "settings" => settings_payload(),
      "database" => safe_section(&database_payload/0),
      "openRecords" => safe_section(&open_records_payload/0),
      "cars" => safe_section(&cars_payload/0)
    }
  end

  defp redaction_payload do
    %{
      "mode" => "allowlist",
      "omitted" => [
        "tesla tokens",
        "passwords",
        "mqtt credentials",
        "environment variables",
        "VINs",
        "car display names",
        "exact coordinates",
        "raw logs",
        "file paths",
        "configured URLs"
      ]
    }
  end

  defp app_payload do
    %{
      "version" => Application.spec(:teslamate, :vsn) |> version_string(),
      "elixir" => System.version(),
      "otpRelease" => :erlang.system_info(:otp_release) |> to_string(),
      "uptimeSeconds" => uptime_seconds(),
      "processCount" => :erlang.system_info(:process_count),
      "memoryBytes" => memory_payload()
    }
  end

  defp runtime_payload do
    %{
      "import" => safe_section(&import_payload/0),
      "mqtt" => safe_section(&mqtt_payload/0)
    }
  end

  defp import_payload do
    configured = Application.get_env(:teslamate, :import_directory) != nil
    enabled = Import.enabled?()

    %{
      "configured" => configured,
      "running" => if(enabled, do: Import.running?(), else: false)
    }
  end

  defp mqtt_payload do
    case Application.get_env(:teslamate, :mqtt) do
      nil ->
        %{"configured" => false, "tls" => false}

      opts ->
        %{
          "configured" => true,
          "tls" => Keyword.get(opts, :tls, false)
        }
    end
  end

  defp settings_payload do
    %{
      "global" => safe_section(&global_settings_payload/0)
    }
  end

  defp global_settings_payload do
    settings = Settings.get_global_settings!()

    %{
      "unitOfLength" => enum_value(settings.unit_of_length),
      "unitOfTemperature" => enum_value(settings.unit_of_temperature),
      "unitOfPressure" => enum_value(settings.unit_of_pressure),
      "preferredRange" => enum_value(settings.preferred_range),
      "language" => settings.language,
      "themeMode" => enum_value(settings.theme_mode),
      "baseUrlConfigured" => present?(settings.base_url),
      "grafanaUrlConfigured" => present?(settings.grafana_url)
    }
  end

  defp database_payload do
    %{
      "status" => "ok",
      "postgres" => postgres_payload(),
      "schema" => schema_payload(),
      "tableCounts" => table_counts_payload()
    }
  end

  defp postgres_payload do
    case SQL.query(
           Repo,
           """
           SELECT regexp_replace(version(), 'PostgreSQL ([^ ]+) .*', '\\1') AS version,
                  current_setting('server_version_num')::integer AS version_num
           """,
           []
         ) do
      {:ok, %{rows: [[version, version_num] | _]}} ->
        %{
          "version" => version,
          "versionNum" => version_num,
          "major" => div(version_num, 10_000)
        }

      {:ok, _} ->
        %{"status" => "unavailable"}

      {:error, error} ->
        %{"status" => "error", "error" => error_payload(error)}
    end
  end

  defp schema_payload do
    from(m in "schema_migrations",
      select: %{
        latest: max(field(m, :version)),
        count: count()
      }
    )
    |> Repo.one()
    |> case do
      %{latest: latest, count: count} ->
        %{"latestMigration" => latest, "migrationCount" => count}

      _ ->
        %{"latestMigration" => nil, "migrationCount" => 0}
    end
  end

  defp table_counts_payload do
    %{
      "cars" => row_count(Car),
      "drives" => row_count(Drive),
      "positions" => row_count(Position),
      "chargingProcesses" => row_count(ChargingProcess),
      "charges" => row_count(Charge),
      "states" => row_count(State),
      "updates" => row_count(Update),
      "geofences" => row_count(GeoFence)
    }
  end

  defp open_records_payload do
    %{
      "drives" =>
        Drive
        |> where([d], is_nil(d.end_date))
        |> row_count(),
      "chargingProcesses" =>
        ChargingProcess
        |> where([c], is_nil(c.end_date))
        |> row_count()
    }
  end

  defp cars_payload do
    from(c in Car,
      join: s in CarSettings,
      on: c.settings_id == s.id,
      order_by: c.id,
      select: %{
        "id" => c.id,
        "settings" => %{
          "enabled" => s.enabled,
          "useStreamingApi" => s.use_streaming_api,
          "lfpBattery" => s.lfp_battery,
          "requireLocked" => s.req_not_unlocked,
          "freeSupercharging" => s.free_supercharging,
          "suspendMinutes" => s.suspend_min,
          "suspendAfterIdleMinutes" => s.suspend_after_idle_min
        }
      }
    )
    |> Repo.all()
  end

  defp row_count(queryable), do: Repo.aggregate(queryable, :count, :id)

  defp safe_section(fun) do
    fun.()
  rescue
    error -> %{"status" => "error", "error" => error_payload(error)}
  end

  defp error_payload(error) do
    %{
      "type" => error.__struct__ |> inspect(),
      "message" => error |> Exception.message() |> redact()
    }
  end

  defp redact(message) do
    message
    |> String.replace(
      ~r/(password|token|secret|authorization|cookie)[^,\n\r]*/i,
      "\\1=<redacted>"
    )
    |> String.replace(~r/https?:\/\/[^\s"']+/i, "https://<redacted>")
    |> String.replace(~r/(^|[\s"'`])\/[^\s"'`,]+/, "\\1/<redacted-path>")
    |> String.replace(
      ~r/(^|[^A-Z0-9])(?=[A-HJ-NPR-Z0-9]{0,16}[A-HJ-NPR-Z])([A-HJ-NPR-Z0-9]{17})(?=[^A-Z0-9]|$)/i,
      "\\1<redacted>"
    )
    |> String.slice(0, 240)
  end

  defp memory_payload do
    :erlang.memory()
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp uptime_seconds do
    {milliseconds, _} = :erlang.statistics(:wall_clock)
    div(milliseconds, 1_000)
  end

  defp version_string(nil), do: "unknown"
  defp version_string(version), do: to_string(version)

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
