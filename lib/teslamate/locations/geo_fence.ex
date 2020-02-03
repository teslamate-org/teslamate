defmodule TeslaMate.Locations.GeoFence do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import TeslaMate.CustomExpressions, only: [within_geofence?: 3]

  alias TeslaMate.Log.Car

  schema "geofences" do
    field :name, :string
    field :latitude, :float
    field :longitude, :float
    field :radius, :float

    field :cost_per_kwh, :decimal

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
      :longitude,
      :cost_per_kwh
    ])
    |> put_assoc_if(attrs, :sleep_mode_blacklist)
    |> put_assoc_if(attrs, :sleep_mode_whitelist)
    |> validate_required([:name, :latitude, :longitude, :radius])
    |> validate_number(:radius, greater_than: 0, less_than: 1000)
    |> validate_number(:cost_per_kwh, greater_than_or_equal_to: 0)
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
