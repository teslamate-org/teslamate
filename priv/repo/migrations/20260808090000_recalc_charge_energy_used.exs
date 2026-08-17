defmodule TeslaMate.Repo.Migrations.RecalcChargeEnergyUsed do
  use Ecto.Migration

  # charge_energy_used is a stored aggregate; processes completed before the
  # phase-detection fallback no longer match what the current formula
  # computes. Recompute the stored values so every installation converges on
  # the current formula via the upgrade path. Only rows whose value actually
  # changes are written, an existing value is never overwritten with NULL,
  # and cost is left untouched since it may have been edited manually.
  def up do
    execute("""
    WITH detection AS (
      SELECT c.charging_process_id AS cp_id,
             avg(c.charger_power * 1000.0 / nullif(c.charger_actual_current::int * c.charger_voltage, 0)) AS p,
             avg(c.charger_phases)::int AS r,
             count(*) AS n
      FROM charges c
      GROUP BY 1
    ), phases AS (
      SELECT cp_id,
             CASE WHEN p IS NOT NULL AND p > 0 AND n > 15 THEN
               CASE WHEN r = round(p) THEN r::float
                    WHEN r = 3 AND abs(p / sqrt(3.0) - 1) <= 0.1 THEN sqrt(3.0)
                    WHEN round(p) > 0 AND abs(round(p) - p) <= 0.3 THEN round(p)::float
               END
             END AS ph
      FROM detection
    ), integrated AS (
      SELECT c.charging_process_id AS cp_id,
             CASE WHEN c.charger_phases IS NULL THEN c.charger_power::float
                  ELSE coalesce(c.charger_actual_current::int * c.charger_voltage * ph.ph / 1000.0, c.charger_power)
             END *
             EXTRACT(epoch FROM (c.date - lag(c.date) OVER (PARTITION BY c.charging_process_id ORDER BY c.date))) / 3600 AS energy
      FROM charges c
      JOIN phases ph ON ph.cp_id = c.charging_process_id
    ), recomputed AS (
      SELECT cp_id,
             round(sum(energy) FILTER (WHERE energy >= 0)::numeric, 2) AS used
      FROM integrated
      GROUP BY 1
    )
    UPDATE charging_processes cp
    SET charge_energy_used = r.used
    FROM recomputed r
    WHERE cp.id = r.cp_id
      AND r.used IS NOT NULL
      AND cp.charge_energy_used IS DISTINCT FROM r.used
    """)
  end

  def down do
    # The pre-migration values are not preserved; recomputing with the
    # previous formula would reintroduce the dropped rows.
    :ok
  end
end
