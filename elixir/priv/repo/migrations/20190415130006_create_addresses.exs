defmodule TeslaMate.Repo.Migrations.CreateAddresses do
  use Ecto.Migration

  def change do
    create table(:addresses) do
      add(:display_name, :string, size: 512)
      add(:place_id, :integer)
      add(:latitude, :float)
      add(:longitude, :float)
      add(:name, :string)
      add(:house_number, :string)
      add(:road, :string)
      add(:neighbourhood, :string)
      add(:city, :string)
      add(:county, :string)
      add(:postcode, :string)
      add(:state, :string)
      add(:state_district, :string)
      add(:country, :string)
      add(:raw, :map)

      timestamps()
    end

    create(unique_index(:addresses, :place_id))
  end
end
