defmodule TeslaMate.Repo.Migrations.AddAccountEmailTokens do
  use Ecto.Migration

  def change do
    alter table(:tokens) do
      add :account_email, :string, null: false
    end

    create(unique_index(:tokens, :account_email))
  end
end
