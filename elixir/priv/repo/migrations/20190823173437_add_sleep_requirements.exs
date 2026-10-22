defmodule TeslaMate.Repo.Migrations.AddSleepRequirements do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add(:req_no_shift_state_reading, :boolean, null: false, default: false)
      add(:req_no_temp_reading, :boolean, null: false, default: false)
      add(:req_not_unlocked, :boolean, null: false, default: true)
    end
  end
end
