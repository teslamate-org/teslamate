defmodule TeslaMate.Repo.Migrations.AddTirePressures do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :tpms_pressure_fl, :numeric, precision: 4, scale: 1
      add :tpms_pressure_fr, :numeric, precision: 4, scale: 1
      add :tpms_pressure_rl, :numeric, precision: 4, scale: 1
      add :tpms_pressure_rr, :numeric, precision: 4, scale: 1
    end

    execute(
      """
      CREATE OR REPLACE FUNCTION public.convert_tire_pressure(n numeric(6,2), character varying)
      RETURNS numeric(6,2)
      LANGUAGE 'sql'
      COST 100
      VOLATILE
      AS $BODY$
      SELECT
      CASE $2 WHEN 'bar' THEN $1
          WHEN 'psi' THEN $1 * 14.503773773
      END;
      $BODY$;
      """,
      &noop/0
    )
  end

  defp noop, do: :ok
end
