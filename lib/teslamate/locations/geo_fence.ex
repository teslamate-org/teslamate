defmodule TeslaMate.Locations.GeoFence do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import TeslaMate.CustomExpressions, only: [within_geofence?: 3]

  alias TeslaMate.Log.{ChargingProcess, Drive, Car}

  schema "geofences" do
    field :name, :string
    field :latitude, :float
    field :longitude, :float
    field :radius, :float

    has_many :charging_processes, ChargingProcess, foreign_key: :geofence_id

    has_many :drives_start, Drive, foreign_key: :start_geofence_id
    has_many :drives_end, Drive, foreign_key: :end_geofence_id

    many_to_many :sleep_mode_whitelist, Car,
      join_through: "geofence_sleep_mode_whitelist",
      join_keys: [geofence_id: :id, car_id: :id],
      on_replace: :delete,
      unique: true

    many_to_many :sleep_mode_blacklist, Car,
      join_through: "geofence_sleep_mode_blacklist",
      join_keys: [geofence_id: :id, car_id: :id],
      on_replace: :delete,
      unique: true

    timestamps()
  end

  @doc false
  def changeset(geofence, attrs) do
    geofence
    |> cast(attrs, [
      :name,
      :radius,
      :latitude,
      :longitude
    ])
    |> put_assoc_if(attrs, :sleep_mode_blacklist)
    |> put_assoc_if(attrs, :sleep_mode_whitelist)
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

  defp put_assoc_if(changeset, attrs, key) do
    case attrs[key] || attrs["#{key}"] do
      nil -> changeset
      val -> put_assoc(changeset, key, val)
    end
  end

  defp where_exclude(query, %__MODULE__{id: nil}), do: query
  defp where_exclude(query, %__MODULE__{id: id}), do: where(query, [g], g.id != ^id)
end
