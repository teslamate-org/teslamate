defmodule TeslaMate.Repo.Migrations.AddPositionIdsAndApplyGeofences do
  use Ecto.Migration

  import Ecto.Query

  alias TeslaMate.Repo

  defmodule Position do
    use Ecto.Schema
    import Ecto.Changeset

    schema "positions" do
      field(:date, :utc_datetime)
      belongs_to(:drive, Drive)
    end
  end

  defmodule Drive do
    use Ecto.Schema
    import Ecto.Changeset

    schema "drives" do
      belongs_to(:start_position, Position)
      belongs_to(:end_position, Position)
      belongs_to(:start_geofence, GeoFence)
      belongs_to(:end_geofence, GeoFence)
    end

    @doc false
    def changeset(drive, attrs) do
      drive
      |> cast(attrs, [:start_position_id, :end_position_id, :start_geofence_id, :end_geofence_id])
      |> foreign_key_constraint(:start_geofence_id)
      |> foreign_key_constraint(:end_geofence_id)
      |> foreign_key_constraint(:start_position_id)
      |> foreign_key_constraint(:end_position_id)
    end
  end

  defmodule ChargingProcess do
    use Ecto.Schema
    import Ecto.Changeset

    schema "charging_processes" do
      belongs_to(:position, Position)
      belongs_to(:geofence, GeoFence)
    end

    @doc false
    def changeset(charging_state, attrs) do
      charging_state
      |> cast(attrs, [:geo_fence_id])
      |> foreign_key_constraint(:geofence_id)
    end
  end

  defmodule GeoFence do
    use Ecto.Schema

    schema "geofences" do
      field(:latitude, :float)
      field(:longitude, :float)
      field(:radius, :float)
      has_many(:addresses, Address)
    end
  end

  def up do
    Repo.transaction(fn ->
      :ok =
        Drive
        |> select([:id])
        |> Repo.stream()
        |> Stream.each(&add_position_ids/1)
        |> Stream.run()

      for geofence <- Repo.all(GeoFence) do
        :ok = apply_geofence_to_drives(geofence)
        :ok = apply_geofence_to_charges(geofence)
      end
    end)
  end

  def down do
    :ok
  end

  defp add_position_ids(%Drive{id: drive_id}) do
    query =
      Position
      |> select([p], %{
        id: p.id,
        first_row: row_number() |> over(order_by: [asc: p.date]),
        last_row: row_number() |> over(order_by: [desc: p.date])
      })
      |> where(drive_id: ^drive_id)
      |> order_by(asc: :date)

    positions =
      subquery(query)
      |> where([p], p.first_row == 1 or p.last_row == 1)
      |> Repo.all()

    case positions do
      [start_position, end_position] ->
        Repo.get!(Drive, drive_id)
        |> Drive.changeset(%{
          start_position_id: start_position.id,
          end_position_id: end_position.id
        })
        |> Repo.update()

      [start_position] ->
        Repo.get!(Drive, drive_id)
        |> Drive.changeset(%{
          start_position_id: start_position.id
        })
        |> Repo.update()

      [] ->
        IO.inspect(drive_id, label: :no_positions)
    end
  end

  defp apply_geofence_to_drives(%GeoFence{id: id, latitude: lat, longitude: lng, radius: r}) do
    {_, nil} =
      from(d in Drive,
        join: p in Position,
        on: [id: d.start_position_id],
        where:
          fragment(
            "earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?)",
            ^lat,
            ^lng,
            ^r,
            p.latitude,
            p.longitude
          )
      )
      |> Repo.update_all(set: [start_geofence_id: id])

    {_, nil} =
      from(d in Drive,
        join: p in Position,
        on: [id: d.end_position_id],
        where:
          fragment(
            "earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?)",
            ^lat,
            ^lng,
            ^r,
            p.latitude,
            p.longitude
          )
      )
      |> Repo.update_all(set: [end_geofence_id: id])

    :ok
  end

  defp apply_geofence_to_charges(%GeoFence{id: id, latitude: lat, longitude: lng, radius: r}) do
    {_, nil} =
      from(d in ChargingProcess,
        join: p in Position,
        on: [id: d.position_id],
        where:
          fragment(
            "earth_box(ll_to_earth(?, ?), ?) @> ll_to_earth(?, ?)",
            ^lat,
            ^lng,
            ^r,
            p.latitude,
            p.longitude
          )
      )
      |> Repo.update_all(set: [geofence_id: id])

    :ok
  end
end
