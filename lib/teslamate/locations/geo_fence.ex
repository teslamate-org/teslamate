defmodule TeslaMate.Locations.GeoFence do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import TeslaMate.Locations.Functions

  alias TeslaMate.Log.{ChargingProcess, Drive}

  schema "geofences" do
    field :name, :string
    field :latitude, :float
    field :longitude, :float
    field :radius, :float

    has_many :charging_processes, ChargingProcess,
      foreign_key: :geofence_id,
      on_delete: :nilify_all

    has_many :drives_start, Drive, foreign_key: :start_geofence_id, on_delete: :nilify_all
    has_many :drives_end, Drive, foreign_key: :end_geofence_id, on_delete: :nilify_all

    timestamps()
  end

  @doc false
  def changeset(geofence, attrs) do
    geofence
    |> cast(attrs, [:name, :radius, :latitude, :longitude])
    |> validate_required([:name, :latitude, :longitude, :radius])
    |> validate_number(:radius, greater_than: 0, less_than: 1000)
    |> prepare_changes(fn changeset ->
      self = apply_changes(changeset)

      overlapping? =
        __MODULE__
        |> select(count())
        |> where_exclude(self)
        |> where([g], within_geofence?(self, g, :left))
        |> changeset.repo.one() > 0

      if overlapping? do
        add_error(changeset, :latitude, "is overlapping with other geo-fence")
      else
        changeset
      end
    end)
  end

  defp where_exclude(query, %__MODULE__{id: nil}), do: query
  defp where_exclude(query, %__MODULE__{id: id}), do: where(query, [g], g.id != ^id)
end
