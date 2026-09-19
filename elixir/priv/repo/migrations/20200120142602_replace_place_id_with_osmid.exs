defmodule TeslaMate.Repo.Migrations.ReplacePlaceIdWithOsmid do
  use Ecto.Migration

  def change do
    drop(unique_index(:addresses, :place_id))

    alter table(:addresses) do
      remove(:place_id, :integer)
      add(:osm_id, :bigint)
      add(:osm_type, :text)
    end

    create(unique_index(:addresses, [:osm_id, :osm_type]))

    execute("UPDATE drives SET start_address_id = NULL, end_address_id = NULL;", fn -> :ok end)
    execute("UPDATE charging_processes SET address_id = NULL;", fn -> :ok end)
    execute("DELETE FROM addresses;", fn -> :ok end)
    execute("ALTER SEQUENCE addresses_id_seq RESTART;", fn -> :ok end)
  end
end
