defmodule TeslaMate.Repo.Migrations.RepairDrivesWithMissingOdometer do
  use Ecto.Migration

  # Drives closed before the switch from first_value/last_value to min/max kept
  # a NULL start_km, end_km and distance whenever their first or last position
  # carried no odometer. Recompute those three columns from the positions that
  # are still around, so existing installations converge on the values the
  # current code would write.
  #
  # Only rows that are actually broken are touched, and only when the retained
  # positions prove a positive distance: a drive whose positions have since been
  # purged, or that has a single odometer reading left, keeps its NULLs rather
  # than gaining a fabricated 0.
  def up do
    execute("""
    WITH recomputed AS (
      SELECT p.drive_id AS id,
             min(p.odometer) AS start_km,
             max(p.odometer) AS end_km
      FROM positions p
      WHERE p.drive_id IS NOT NULL
        AND p.odometer IS NOT NULL
      GROUP BY 1
    )
    UPDATE drives d
    SET start_km = r.start_km,
        end_km = r.end_km,
        distance = r.end_km - r.start_km
    FROM recomputed r
    WHERE d.id = r.id
      AND (d.start_km IS NULL OR d.end_km IS NULL OR d.distance IS NULL)
      AND r.end_km > r.start_km
    """)
  end

  def down do
    # The previous NULLs carry no information worth restoring.
    :ok
  end
end
