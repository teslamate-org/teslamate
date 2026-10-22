defmodule TeslaMate.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def change do
    create table(:tokens) do
      add(:access, :string, null: false)
      add(:refresh, :string, null: false)

      timestamps()
    end
  end
end
