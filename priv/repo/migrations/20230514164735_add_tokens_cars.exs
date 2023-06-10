defmodule TeslaMate.Repo.Migrations.AddTokensCars do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      add(:tokens_id, references(:tokens), null: true)
    end
  end
end
