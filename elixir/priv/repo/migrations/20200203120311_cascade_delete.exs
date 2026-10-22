defmodule TeslaMate.Repo.Migrations.CascadeDelete do
  use Ecto.Migration

  def up do
    drop(constraint(:cars, "cars_settings_id_fkey"))

    flush()

    alter table(:cars) do
      modify(:settings_id, references(:car_settings, on_delete: :delete_all), null: false)
    end

    drop(constraint(:charges, "charges_charging_process_id_fkey"))

    flush()

    alter table(:charges) do
      modify(:charging_process_id, references(:charging_processes, on_delete: :delete_all),
        null: false
      )
    end

    drop(constraint(:charging_processes, "charging_processes_car_id_fkey"))
    drop(constraint(:charging_processes, "charging_processes_address_id_fkey"))
    drop(constraint(:charging_processes, "charging_processes_geofence_id_fkey"))

    flush()

    alter table(:charging_processes) do
      modify(:car_id, references(:cars, on_delete: :delete_all), null: false)
      modify(:address_id, references(:addresses, on_delete: :nilify_all))
      modify(:geofence_id, references(:geofences, on_delete: :nilify_all))
    end

    drop_if_exists(constraint(:drives, "trips_car_id_fkey"))
    drop_if_exists(constraint(:drives, "drives_car_id_fkey"))

    drop(constraint(:drives, "drives_start_position_id_fkey"))
    drop(constraint(:drives, "drives_end_position_id_fkey"))

    drop_if_exists(constraint(:drives, "trips_start_address_id_fkey"))
    drop_if_exists(constraint(:drives, "trips_end_address_id_fkey"))
    drop_if_exists(constraint(:drives, "drives_start_address_id_fkey"))
    drop_if_exists(constraint(:drives, "drives_end_address_id_fkey"))

    drop(constraint(:drives, "drives_start_geofence_id_fkey"))
    drop(constraint(:drives, "drives_end_geofence_id_fkey"))

    flush()

    alter table(:drives) do
      modify(:car_id, references(:cars, on_delete: :delete_all), null: false)

      modify(:start_position_id, references(:positions, on_delete: :nilify_all))
      modify(:end_position_id, references(:positions, on_delete: :nilify_all))

      modify(:start_address_id, references(:addresses, on_delete: :nilify_all))
      modify(:end_address_id, references(:addresses, on_delete: :nilify_all))

      modify(:start_geofence_id, references(:geofences, on_delete: :nilify_all))
      modify(:end_geofence_id, references(:geofences, on_delete: :nilify_all))
    end

    drop(constraint(:positions, "positions_car_id_fkey"))
    drop(constraint(:positions, "positions_drive_id_fkey"))

    flush()

    alter table(:positions) do
      modify(:car_id, references(:cars, on_delete: :delete_all), null: false)
      modify(:drive_id, references(:drives, on_delete: :nilify_all))
    end

    drop(constraint(:states, "states_car_id_fkey"))

    flush()

    alter table(:states) do
      modify(:car_id, references(:cars, on_delete: :delete_all), null: false)
    end

    drop(constraint(:updates, "updates_car_id_fkey"))

    flush()

    alter table(:updates) do
      modify(:car_id, references(:cars, on_delete: :delete_all), null: false)
    end
  end

  def down do
    :ok
  end
end
