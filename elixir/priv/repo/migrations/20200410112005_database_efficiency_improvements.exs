defmodule TeslaMate.Repo.Migrations.DatabaseEfficiencyImprovements do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      modify(:id, :smallint)
    end

    alter table(:addresses) do
      modify(:id, :integer)
      modify(:latitude, :numeric, precision: 8, scale: 6)
      modify(:longitude, :numeric, precision: 9, scale: 6)
    end

    alter table(:charging_processes) do
      modify(:id, :integer)
      modify(:charge_energy_added, :numeric, precision: 8, scale: 2)
      modify(:charge_energy_used, :numeric, precision: 8, scale: 2)
      modify(:start_ideal_range_km, :numeric, precision: 6, scale: 2)
      modify(:end_ideal_range_km, :numeric, precision: 6, scale: 2)
      modify(:start_rated_range_km, :numeric, precision: 6, scale: 2)
      modify(:end_rated_range_km, :numeric, precision: 6, scale: 2)
      modify(:start_battery_level, :smallint)
      modify(:end_battery_level, :smallint)
      modify(:duration_min, :smallint)
      modify(:outside_temp_avg, :numeric, precision: 4, scale: 1)
      modify(:car_id, :smallint)
      modify(:position_id, :integer)
      modify(:address_id, :integer)
      modify(:geofence_id, :integer)
    end

    alter table(:drives) do
      modify(:id, :integer)
      modify(:car_id, :smallint)
      modify(:outside_temp_avg, :numeric, precision: 4, scale: 1)
      modify(:inside_temp_avg, :numeric, precision: 4, scale: 1)
      modify(:speed_max, :smallint)
      modify(:power_max, :smallint)
      modify(:power_min, :smallint)
      modify(:start_ideal_range_km, :numeric, precision: 6, scale: 2)
      modify(:end_ideal_range_km, :numeric, precision: 6, scale: 2)
      modify(:start_rated_range_km, :numeric, precision: 6, scale: 2)
      modify(:end_rated_range_km, :numeric, precision: 6, scale: 2)
      modify(:duration_min, :smallint)
      modify(:start_position_id, :integer)
      modify(:end_position_id, :integer)
      modify(:start_address_id, :integer)
      modify(:end_address_id, :integer)
      modify(:start_geofence_id, :integer)
      modify(:end_geofence_id, :integer)
    end

    alter table(:geofences) do
      modify(:id, :integer)
      modify(:latitude, :numeric, precision: 8, scale: 6)
      modify(:longitude, :numeric, precision: 9, scale: 6)
      modify(:radius, :smallint)
    end

    alter table(:positions) do
      modify(:id, :integer)
      modify(:car_id, :smallint)
      modify(:drive_id, :integer)
      modify(:latitude, :numeric, precision: 8, scale: 6)
      modify(:longitude, :numeric, precision: 9, scale: 6)
      modify(:elevation, :smallint)
      modify(:speed, :smallint)
      modify(:power, :smallint)
      modify(:ideal_battery_range_km, :numeric, precision: 6, scale: 2)
      modify(:est_battery_range_km, :numeric, precision: 6, scale: 2)
      modify(:rated_battery_range_km, :numeric, precision: 6, scale: 2)
      modify(:battery_level, :smallint)
      modify(:usable_battery_level, :smallint)
      modify(:outside_temp, :numeric, precision: 4, scale: 1)
      modify(:inside_temp, :numeric, precision: 4, scale: 1)
      modify(:driver_temp_setting, :numeric, precision: 4, scale: 1)
      modify(:passenger_temp_setting, :numeric, precision: 4, scale: 1)
    end

    alter table(:charges) do
      modify(:id, :integer)
      modify(:charging_process_id, :integer)
      modify(:battery_level, :smallint)
      modify(:usable_battery_level, :smallint)
      modify(:charge_energy_added, :numeric, precision: 8, scale: 2)
      modify(:charger_actual_current, :smallint)
      modify(:charger_phases, :smallint)
      modify(:charger_pilot_current, :smallint)
      modify(:charger_power, :smallint)
      modify(:charger_voltage, :smallint)
      modify(:ideal_battery_range_km, :numeric, precision: 6, scale: 2)
      modify(:rated_battery_range_km, :numeric, precision: 6, scale: 2)
      modify(:outside_temp, :numeric, precision: 4, scale: 1)
    end

    alter table(:states) do
      modify(:id, :integer)
      modify(:car_id, :smallint)
    end

    alter table(:tokens) do
      modify(:id, :integer)
    end

    alter table(:updates) do
      modify(:id, :integer)
      modify(:car_id, :smallint)
    end
  end
end
