# Schemas

defmodule Drive do
  use Ecto.Schema
  import Ecto.Changeset

  schema "drives" do
    field(:start_ideal_range_km, :float)
    field(:end_ideal_range_km, :float)
    field(:start_rated_range_km, :float)
    field(:end_rated_range_km, :float)
  end

  @doc false
  def changeset(drive, attrs) do
    drive
    |> cast(attrs, [
      :start_ideal_range_km,
      :end_ideal_range_km,
      :start_rated_range_km,
      :end_rated_range_km
    ])
  end
end

defmodule Position do
  use Ecto.Schema
  import Ecto.Changeset

  schema "positions" do
    field(:date, :utc_datetime)
    field(:ideal_battery_range_km, :float)
    field(:rated_battery_range_km, :float)

    belongs_to(:drive, Drive)
  end

  @doc false
  def changeset(position, attrs) do
    position
    |> cast(attrs, [:date, :ideal_battery_range_km, :rated_battery_range_km])
    |> validate_required([:date])
    |> foreign_key_constraint(:drive_id)
  end
end

# Migration

defmodule TeslaMate.Repo.Migrations.SetStartAndEndRatedRangeKm do
  use Ecto.Migration

  alias TeslaMate.Repo
  import Ecto.Query

  defp add_rated_range(%Drive{id: drive_id} = drive) do
    query =
      Position
      |> select([p], %{
        rated_battery_range_km: p.rated_battery_range_km,
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
      [start_pos, end_pos] ->
        {:ok, _drive} =
          drive
          |> Drive.changeset(%{
            start_rated_range_km: start_pos.rated_battery_range_km,
            end_rated_range_km: end_pos.rated_battery_range_km
          })
          |> Repo.update()

      _ ->
        :ok
    end
  end

  def up do
    Repo.transaction(fn ->
      Drive
      |> where([d], is_nil(d.start_rated_range_km) or is_nil(d.end_rated_range_km))
      |> order_by(asc: :id)
      |> Repo.stream()
      |> Stream.each(&add_rated_range/1)
      |> Stream.run()
    end)
  end

  def down do
    :ok
  end
end
