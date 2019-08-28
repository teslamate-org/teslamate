defmodule TeslaMate.Repo.Migrations.AddMToFtConversionHelper do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION convert_m(n double precision, unit text)
    RETURNS double precision
    AS $$
      SELECT
        CASE WHEN $2 = 'm' THEN $1
             WHEN $2 = 'ft' THEN $1 * 3.28084
        END;
    $$
    LANGUAGE SQL
    IMMUTABLE
    RETURNS NULL ON NULL INPUT;
    """)
  end

  def down do
    execute("drop function convert_m;")
  end
end
