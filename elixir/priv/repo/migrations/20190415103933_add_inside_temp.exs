defmodule TeslaMate.Repo.Migrations.AddInsideTemp do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add(:inside_temp, :float)
    end

    alter table(:trips) do
      add(:inside_temp_avg, :float)
    end
  end
end
