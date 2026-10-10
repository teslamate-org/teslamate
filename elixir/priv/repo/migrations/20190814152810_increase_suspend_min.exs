defmodule TeslaMate.Repo.Migrations.IncreaseSuspendMin do
  use Ecto.Migration

  import Ecto.Query

  alias TeslaMate.Repo

  def up do
    alter table(:settings) do
      modify(:suspend_min, :integer, default: 21, null: false)
    end

    flush()

    from(s in "settings",
      update: [set: [suspend_min: 21]],
      where: s.suspend_min < 21
    )
    |> Repo.update_all([])
  end

  def down do
    :ok
  end
end
