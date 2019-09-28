defmodule TeslaMate.Repo.Migrations.AddBaseUrlSetting do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add(:base_url, :string, null: true)
    end
  end
end
