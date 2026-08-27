defmodule TeslaMate.Repo.Migrations.AddNotNullConstraintToVin do
  use Ecto.Migration

  @legacy_vin_prefix "__legacy_null_vin__:"

  def up do
    # Preserve old cars and their history; vehicle discovery replaces this marker via eid or vid.
    execute("""
    UPDATE cars
    SET vin = '#{@legacy_vin_prefix}' || id::text
    WHERE vin IS NULL
    """)

    alter table(:cars) do
      modify(:vin, :text, null: false)
    end
  end

  def down do
    alter table(:cars) do
      modify(:vin, :text, null: true)
    end

    execute("""
    UPDATE cars
    SET vin = NULL
    WHERE vin = '#{@legacy_vin_prefix}' || id::text
    """)
  end
end
