defmodule TeslaMate.Repo.Migrations.AddMarketingNameToCar do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      add :marketing_name, :string, null: true
    end
  end
end
