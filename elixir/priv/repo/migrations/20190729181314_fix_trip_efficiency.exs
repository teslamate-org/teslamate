defmodule TeslaMate.Repo.Migrations.FixTripEfficiency do
  use Ecto.Migration

  import Ecto.Query

  def up do
    from(t in "trips",
      update: [set: [efficiency: 1 / t.efficiency]],
      where: not is_nil(t.efficiency)
    )
    |> TeslaMate.Repo.update_all([])
  end

  def down do
    from(t in "trips",
      update: [set: [efficiency: 1 / t.efficiency]],
      where: not is_nil(t.efficiency)
    )
    |> TeslaMate.Repo.update_all([])
  end
end
