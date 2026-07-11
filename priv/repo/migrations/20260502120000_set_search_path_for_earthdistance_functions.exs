defmodule TeslaMate.Repo.Migrations.SetSearchPathForEarthdistanceFunctions do
  use Ecto.Migration

  def up do
    execute("ALTER FUNCTION ll_to_earth SET search_path = public")
    execute("ALTER FUNCTION earth_box SET search_path = public")
  end

  def down do
    :ok
  end
end
