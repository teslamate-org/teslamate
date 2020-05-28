defmodule TeslaMate.Repo.Migrations.OptimizeConversionHelpers do
  use Ecto.Migration

  def change do
    execute("DROP FUNCTION public.convert_km(double precision, text);", &noop/0)

    execute(
      """
      CREATE OR REPLACE FUNCTION public.convert_km(n numeric(6,2), unit text)
      RETURNS numeric(6,2)
      LANGUAGE 'sql'
      COST 100
      VOLATILE
      AS $BODY$
        SELECT
        CASE $2 WHEN 'km' THEN $1
                WHEN 'mi' THEN $1 / 1.60934
        END;
      $BODY$;
      """,
      &noop/0
    )

    execute("DROP FUNCTION public.convert_celsius(double precision, text);", &noop/0)

    execute(
      """
      CREATE OR REPLACE FUNCTION public.convert_celsius(n numeric(4,1), unit text)
      RETURNS numeric(4,1)
      LANGUAGE 'sql'
      COST 100
      VOLATILE
      AS $BODY$
        SELECT
        CASE $2 WHEN 'C' THEN $1
                WHEN 'F' THEN ($1 * 9 / 5) + 32
        END;
      $BODY$;
      """,
      &noop/0
    )
  end

  defp noop, do: :ok
end
