defmodule TeslaMate.Repo.Migrations.AddVehicleConfigAttrbitues do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      add(:exterior_color, :text)
      add(:spoiler_type, :text)
      add(:wheel_type, :text)
    end
  end
end
