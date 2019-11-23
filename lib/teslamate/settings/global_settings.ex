defmodule TeslaMate.Settings.GlobalSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Settings.{Units, Range}

  schema "settings" do
    field :unit_of_length, Units.Length
    field :unit_of_temperature, Units.Temperature

    field :preferred_range, Range

    field :base_url, :string
    field :grafana_url, :string

    timestamps()
  end

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, [
      :unit_of_length,
      :unit_of_temperature,
      :preferred_range,
      :base_url,
      :grafana_url
    ])
    |> validate_required([
      :unit_of_length,
      :unit_of_temperature,
      :preferred_range
    ])
    |> update_change(:base_url, &trim_url/1)
    |> update_change(:grafana_url, &trim_url/1)
    |> validate_url(:base_url)
    |> validate_url(:grafana_url)
  end

  defp trim_url(url) do
    with str when is_binary(str) <- url,
         "" <- str |> String.trim() |> String.trim_trailing("/") do
      nil
    end
  end

  def validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: nil} -> [{field, "is missing a scheme (e.g. https)"}]
        %URI{scheme: scheme} when scheme not in ["http", "https"] -> [{field, "invalid scheme"}]
        %URI{host: nil} -> [{field, "is missing a host"}]
        _valid_uri -> []
      end
    end)
  end
end
