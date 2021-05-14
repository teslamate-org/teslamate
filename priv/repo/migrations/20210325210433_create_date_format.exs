defmodule TeslaMate.Repo.Migrations.CreateDateFormat do
  use Ecto.Migration

  def up do
    execute("CREATE TYPE date_formats AS ENUM ('ISO', 'US')")

    alter table(:settings) do
      add(:date_format, :date_formats, default: "ISO", null: false)
    end
  end

  def down do
    alter table(:settings) do
      remove(:date_format)
    end

    execute("DROP TYPE IF EXISTS date_formats")
  end
end
