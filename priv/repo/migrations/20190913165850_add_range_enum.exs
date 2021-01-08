defmodule TeslaMate.Repo.Migrations.AddRangeEnum do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE range AS ENUM ('ideal', 'rated')", "DROP TYPE range"

    alter table(:settings) do
      add :preferred_range, :range, default: "rated", null: false
    end
  end
end
