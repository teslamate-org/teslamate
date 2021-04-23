defmodule TeslaMate.Repo.Migrations.CreateDateFormat do
  use Ecto.Migration

  def change do
    execute("CREATE TYPE date_formats AS ENUM ('European', 'American')")

    alter table(:settings) do
      add(:date_format, :date_formats, default: "European", null: false)
    end
  end
end
