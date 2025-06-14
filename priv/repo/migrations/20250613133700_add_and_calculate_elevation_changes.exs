defmodule TeslaMate.Repo.Migrations.AddAndCalculateElevationChanges do
  use Ecto.Migration

  def up do
    alter table(:drives) do
      add :ascent, :smallint
      add :descent, :smallint
    end

    execute """
    WITH elevation_changes AS (
      SELECT
        drive_id,
        SUM(CASE WHEN elevation_diff > 0 THEN elevation_diff ELSE 0 END) as ascent,
        SUM(CASE WHEN elevation_diff < 0 THEN ABS(elevation_diff) ELSE 0 END) as descent
      FROM (
        SELECT
          drive_id,
          elevation - LAG(elevation) OVER (PARTITION BY drive_id ORDER BY date) as elevation_diff
        FROM positions
        WHERE elevation IS NOT NULL
      ) as changes
      GROUP BY drive_id
    )
    UPDATE drives d
    SET
      ascent = ec.ascent,
      descent = ec.descent
    FROM elevation_changes ec
    WHERE d.id = ec.drive_id;
    """
  end

  def down do
    alter table(:drives) do
      remove :ascent
      remove :descent
    end
  end
end
