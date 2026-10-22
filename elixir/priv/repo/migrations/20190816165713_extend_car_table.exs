defmodule TeslaMate.Repo.Migrations.ExtendCarTable do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      add(:vin, :text)
      add(:name, :text)
      add(:version, :text)
    end
  end
end
