defmodule TeslaMate.Repo.Migrations.IncreaseGeofenceCostPrecision do
  use Ecto.Migration

  @legacy_max_cost_per_unit "99.9999"
  @legacy_max_fixed_cost "9999.99"

  def up do
    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 14, scale: 2)
    end

    alter table(:geofences) do
      modify(:cost_per_unit, :decimal, precision: 9, scale: 4)
      modify(:session_fee, :decimal, precision: 14, scale: 2)
    end
  end

  def down do
    # Do not silently truncate or discard costs that cannot fit the old schema.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM geofences
        WHERE ABS(cost_per_unit) > #{@legacy_max_cost_per_unit}
      ) THEN
        RAISE EXCEPTION
          'cannot restore geofences.cost_per_unit to numeric(6,4): values exceed #{@legacy_max_cost_per_unit}';
      END IF;

      IF EXISTS (
        SELECT 1 FROM geofences
        WHERE ABS(session_fee) > #{@legacy_max_fixed_cost}
      ) THEN
        RAISE EXCEPTION
          'cannot restore geofences.session_fee to numeric(6,2): values exceed #{@legacy_max_fixed_cost}';
      END IF;

      IF EXISTS (
        SELECT 1 FROM charging_processes
        WHERE ABS(cost) > #{@legacy_max_fixed_cost}
      ) THEN
        RAISE EXCEPTION
          'cannot restore charging_processes.cost to numeric(6,2): values exceed #{@legacy_max_fixed_cost}';
      END IF;
    END
    $$;
    """)

    alter table(:geofences) do
      modify(:cost_per_unit, :decimal, precision: 6, scale: 4)
      modify(:session_fee, :decimal, precision: 6, scale: 2)
    end

    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 6, scale: 2)
    end
  end
end
