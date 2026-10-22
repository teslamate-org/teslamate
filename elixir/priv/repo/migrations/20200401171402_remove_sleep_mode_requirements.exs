defmodule TeslaMate.Repo.Migrations.RemoveSleepModeRequirements do
  use Ecto.Migration

  def change do
    alter table(:car_settings) do
      remove(:req_no_shift_state_reading, :boolean, null: false, default: false)
      remove(:req_no_temp_reading, :boolean, null: false, default: false)
    end
  end
end
