defmodule TeslaMate.Repo.Migrations.EnforcePositiveChargerPhases do
  use Ecto.Migration

  def up do
    # A phase count of 0 (or less) was never meaningful; NULL routes those rows
    # through the charger_power branch of the energy integration.
    execute("""
    UPDATE charges
    SET charger_phases = NULL
    WHERE charger_phases <= 0
    """)

    create(constraint(:charges, :positive_charger_phases, check: "charger_phases > 0"))
  end

  def down do
    # The 0 -> NULL correction is not reversible.
    drop(constraint(:charges, :positive_charger_phases))
  end
end
