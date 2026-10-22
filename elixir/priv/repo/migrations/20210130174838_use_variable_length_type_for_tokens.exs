defmodule TeslaMate.Repo.Migrations.UseVariableLengthTypeForTokens do
  use Ecto.Migration

  def change do
    alter table(:tokens) do
      modify :access, :text, from: :string
      modify :refresh, :text, from: :string
    end
  end
end
