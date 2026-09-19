defmodule TeslaMate.Repo.Migrations.UpgradeEarthdistance do
  use Ecto.Migration

  def change do
    execute("ALTER EXTENSION earthdistance UPDATE")
  end
end
