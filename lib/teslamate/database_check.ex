defmodule TeslaMate.DatabaseCheck do
  alias Ecto.Adapters.SQL
  alias TeslaMate.Repo

  defmodule Version do
    defstruct [:version_string, :version_num, :major]
  end

  @version_requirements %{
    1600 => %{min_version: "16.7", min_version_num: 160_007},
    1700 => %{min_version: "17.3", min_version_num: 170_003}
  }

  def check_postgres_version do
    {:ok, _pid} = Repo.start_link()

    version = get_postgres_version()
    check_compatibility(version)

    Repo.stop()
  end

  defp get_postgres_version do
    {:ok, result} =
      SQL.query(
        Repo,
        """
        SELECT regexp_replace(version(), 'PostgreSQL ([^ ]+) .*', '\\1') AS version,
               current_setting('server_version_num')::integer AS version_num
        """,
        []
      )

    [version_string, version_num] = List.first(result.rows)

    # https://www.postgresql.org/docs/current/libpq-status.html#LIBPQ-PQSERVERVERSION
    major = div(version_num, 100)

    %Version{
      version_string: version_string,
      version_num: version_num,
      major: major
    }
  end

  defp check_compatibility(%Version{
         major: major,
         version_string: version,
         version_num: version_num
       }) do
    cond do
      major > 1700 ->
        IO.puts(
          "PostgreSQL version #{version} is not officially tested or supported yet. Use at your own risk."
        )

      not Map.has_key?(@version_requirements, major) ->
        supported_versions =
          @version_requirements
          |> Map.values()
          |> Enum.map_join(" and ", & &1.min_version)

        raise "PostgreSQL version #{version} is not supported. Only #{supported_versions} are supported."

      version_num < @version_requirements[major].min_version_num ->
        raise "PostgreSQL version #{version} is not supported. Minimum required for #{div(major, 100)}.x is #{@version_requirements[major].min_version}."

      true ->
        IO.puts("PostgreSQL version #{version} is compatible (#{div(major, 100)}.x series).")
    end
  end
end
