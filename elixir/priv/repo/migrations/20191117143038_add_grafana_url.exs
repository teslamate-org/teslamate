defmodule TeslaMate.Repo.Migrations.AddGrafanaUrl do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add(:grafana_url, :string, null: true)
    end
  end
end
