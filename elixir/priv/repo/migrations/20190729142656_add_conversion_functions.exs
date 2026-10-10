defmodule TeslaMate.Repo.Migrations.AddConversionFunctions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION convert_celsius(n double precision, unit text)
    RETURNS double precision
    AS $$
      SELECT
        CASE WHEN $2 = 'C' THEN $1
             WHEN $2 = 'F' THEN ($1 * 9 / 5) + 32
        END;
    $$
    LANGUAGE SQL
    IMMUTABLE
    RETURNS NULL ON NULL INPUT;
    """)

    execute("""
    CREATE FUNCTION convert_km(n double precision, unit text)
    RETURNS double precision
    AS $$
      SELECT
        CASE WHEN $2 = 'km' THEN $1
             WHEN $2 = 'mi' THEN $1 / 1.60934
        END;
    $$
    LANGUAGE SQL
    IMMUTABLE
    RETURNS NULL ON NULL INPUT;
    """)
  end

  def down do
    execute("drop function convert_celsius;")
    execute("drop function convert_km;")
  end
end
