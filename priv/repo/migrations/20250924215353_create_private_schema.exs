defmodule TeslaMate.Repo.Migrations.CreatePrivateSchema do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS private;")
    execute("ALTER TABLE public.tokens SET SCHEMA private;")
  end

  def down do
    execute("ALTER TABLE private.tokens SET SCHEMA public;")
    execute("DROP SCHEMA private;")
  end
end
