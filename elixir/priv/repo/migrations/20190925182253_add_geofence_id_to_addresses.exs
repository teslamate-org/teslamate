defmodule New do
  defmodule GeoFence do
    use Ecto.Schema
    import Ecto.Changeset

    schema "geofences" do
      field(:latitude, :float)
      field(:longitude, :float)
      field(:radius, :float)
      has_many(:addresses, Address)
    end
  end

  defmodule Address do
    use Ecto.Schema
    import Ecto.Changeset

    alias New.GeoFence

    schema "addresses" do
      field(:latitude, :float)
      field(:longitude, :float)

      belongs_to(:geofence, GeoFence)
    end

    @doc false
    def changeset(address, attrs) do
      address
      |> cast(attrs, [:latitude, :longitude, :geofence_id])
      |> validate_required([:latitude, :longitude])
    end
  end
end

defmodule Old do
  defmodule GeoFence do
    use Ecto.Schema
    import Ecto.Changeset

    alias Old.Address

    schema "geofences" do
      field(:latitude, :float)
      field(:longitude, :float)
      belongs_to(:address, Address)
    end

    @doc false
    def changeset(geofence, attrs) do
      geofence
      |> cast(attrs, [:address_id])
      |> foreign_key_constraint(:address_id)
    end
  end

  defmodule Address do
    use Ecto.Schema

    schema "addresses" do
      field(:place_id, :integer)
    end
  end
end

defmodule TeslaMate.Repo.Migrations.AddGeofenceIdToAddresses do
  use Ecto.Migration

  import Ecto.Query
  alias TeslaMate.Repo

  def up do
    alias New.{GeoFence, Address}

    alter table(:addresses) do
      add(:geofence_id, references(:geofences), null: true)
    end

    alter table(:geofences) do
      remove(:address_id, references(:addresses), null: false)
    end

    create(index(:addresses, :geofence_id))

    flush()

    Repo.transaction(fn ->
      for %GeoFence{id: id, latitude: lat, longitude: lng, radius: r} <- Repo.all(GeoFence) do
        query =
          from(a in Address,
            where:
              fragment(
                "earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?)",
                ^lat,
                ^lng,
                ^r,
                a.latitude,
                a.longitude
              )
          )

        :ok =
          query
          |> Repo.stream()
          |> Stream.each(fn %Address{} = address ->
            address
            |> Address.changeset(%{geofence_id: id})
            |> Repo.update()
          end)
          |> Stream.run()
      end
    end)
  end

  def down do
    alias TeslaMate.Locations.Geocoder
    alias Old.{GeoFence, Address}

    {:ok, _pid} = Application.ensure_all_started(:mojito)

    alter table(:addresses) do
      remove(:geofence_id, references(:geofences), null: true)
    end

    alter table(:geofences) do
      add(:address_id, references(:addresses), null: true)
    end

    flush()

    for %GeoFence{latitude: lat, longitude: lng} = geofence <- Repo.all(GeoFence) do
      with {:ok, %{place_id: place_id}} <- Geocoder.reverse_lookup(lat, lng) do
        %Address{id: id} = Repo.get_by(Address, place_id: place_id)

        geofence
        |> GeoFence.changeset(%{address_id: id})
        |> Repo.update()
      end

      Process.sleep(750)
    end

    drop(constraint(:geofences, "geofences_address_id_fkey"))

    alter table(:geofences) do
      modify(:address_id, references(:addresses), null: false)
    end

    create(unique_index(:geofences, :address_id))
  end
end
