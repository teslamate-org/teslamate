defmodule TeslaMate.Repo.Migrations.RenameTripsToDrives do
  use Ecto.Migration

  def up do
    rename(table(:trips), to: table(:drives))
    rename(table(:positions), :trip_id, to: :drive_id)
    execute("ALTER INDEX positions_trip_id_index RENAME TO positions_drive_id_index;")

    execute(
      "ALTER TABLE positions RENAME CONSTRAINT positions_trip_id_fkey TO positions_drive_id_fkey"
    )
  end

  def down do
    rename(table(:drives), to: table(:trips))
    rename(table(:positions), :drive_id, to: :trip_id)
    execute("ALTER INDEX positions_drive_id_index RENAME TO positions_trip_id_index;")

    execute(
      "ALTER TABLE positions RENAME CONSTRAINT positions_drive_id_fkey TO positions_trip_id_fkey"
    )
  end
end
