defmodule TeslaMate.Locations.GeoFence do
  use Ecto.Schema

  import Ecto.Changeset
  import TeslaMateWeb.Gettext

  schema "geofences" do
    field :name, :string
    field :latitude, :decimal, read_after_writes: true
    field :longitude, :decimal, read_after_writes: true
    field :radius, :integer

    field :billing_type, Ecto.Enum, values: [:per_kwh, :per_minute], read_after_writes: true
    field :cost_per_unit, :decimal, read_after_writes: true
    field :session_fee, :decimal, read_after_writes: true
    field :active, :boolean, read_after_writes: true, default: true
    field :supercharger, :boolean, read_after_writes: true, default: false
    field :provider, :string, read_after_writes: true
    field :country_code, :string, read_after_writes: true
    field :currency_code, :string, read_after_writes: true

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
      :cost_per_unit,
      :session_fee,
      :billing_type,
      :currency_code,
      :country_code,
      :supercharger,
      :provider,
      :active
    ])
    |> validate_required([:name, :latitude, :longitude, :radius, :country_code, :currency_code])
    |> validate_number(:radius, greater_than: 0, less_than: 5000)
    |> validate_number(:session_fee, greater_than_or_equal_to: 0)
    |> validate_length(:country_code, is: 2)
    |> validate_length(:currency_code, is: 3)
    |> validate_format(:country_code, ~r/^[[:upper:]]+/, message: gettext("should be uppercase"))
    |> validate_format(:currency_code, ~r/^[[:upper:]]+/, message: gettext("should be uppercase"))
    |> foreign_key_constraint(:country_code, message: gettext("country code does not exist"))
    |> foreign_key_constraint(:currency_code, message: gettext("currency code does not exist"))
  end
end
