defmodule TeslaMate.Repo.Migrations.CarPriorities do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      add(:display_priority, :int, default: 1)
    end
  end
end
