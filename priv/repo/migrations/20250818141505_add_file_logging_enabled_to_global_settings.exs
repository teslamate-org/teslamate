defmodule TeslaMate.Repo.Migrations.AddWebviewLoggingEnabledToGlobalSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :webview_logging_enabled, :boolean, default: false, null: false
    end
  end
end
