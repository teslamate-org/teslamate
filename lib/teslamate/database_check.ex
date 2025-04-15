defmodule TeslaMate.DatabaseCheck do
  alias Ecto.Adapters.SQL
  alias TeslaMate.Repo

  # Minimum versions for supported major releases
  @min_version_16 "16.7"
  @min_version_17 "17.3"

  def check_postgres_version do
    # Start the Repo manually without running migrations
    {:ok, _pid} = Repo.start_link()

    # Query the PostgreSQL version
    {:ok, result} =
      SQL.query(
        Repo,
        "SELECT regexp_replace(version(), 'PostgreSQL ([^ ]+) .*', '\\1') AS version",
        []
      )

    raw_version = result.rows |> List.first() |> List.first()

    # Normalize to SemVer by appending .0 if needed
    version = normalize_version(raw_version)

    # Split into major and minor parts
    [major, _minor] = String.split(version, ".", parts: 2)
    major_int = String.to_integer(major)

    # Check based on major version
    case major_int do
      16 ->
        case Version.compare(version, normalize_version(@min_version_16)) do
          :lt ->
            raise "PostgreSQL version #{raw_version} is not supported. Minimum required for 16.x is #{@min_version_16}."

          _ ->
            IO.puts("PostgreSQL version #{raw_version} is compatible (16.x series).")
        end

      17 ->
        case Version.compare(version, normalize_version(@min_version_17)) do
          :lt ->
            raise "PostgreSQL version #{raw_version} is not supported. Minimum required for 17.x is #{@min_version_17}."

          _ ->
            IO.puts("PostgreSQL version #{raw_version} is compatible (17.x series).")
        end

      major_int when major_int > 17 ->
        IO.puts(
          "PostgreSQL version #{raw_version} is not officially tested or supported yet. Use at your own risk."
        )

      _ ->
        raise "PostgreSQL version #{raw_version} is not supported. Only 16.x (min #{@min_version_16}) and 17.x (min #{@min_version_17}) are supported."
    end

    # Stop the Repo after the check
    Repo.stop()
  end

  # Helper function to normalize PostgreSQL version to SemVer
  defp normalize_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      [major, minor, patch | _] -> "#{major}.#{minor}.#{patch}"
      _ -> raise "Invalid PostgreSQL version format: #{version}"
    end
  end
end
