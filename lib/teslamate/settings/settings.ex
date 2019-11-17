defmodule TeslaMate.Settings.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Settings.{Units, Range}

  schema "settings" do
    field :unit_of_length, Units.Length
    field :unit_of_temperature, Units.Temperature

    field :suspend_min, :integer
    field :suspend_after_idle_min, :integer

    field :req_no_shift_state_reading, :boolean
    field :req_no_temp_reading, :boolean
    field :req_not_unlocked, :boolean

    field :preferred_range, Range

    field :base_url, :string
    field :grafana_url, :string

    timestamps()
  end

  @all_fields [
    :unit_of_length,
    :unit_of_temperature,
    :suspend_min,
    :suspend_after_idle_min,
    :req_no_shift_state_reading,
    :req_no_temp_reading,
    :req_not_unlocked,
    :preferred_range,
    :base_url,
    :grafana_url
  ]

  @req_fields @all_fields -- [:base_url, :grafana_url]

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, @all_fields)
    |> validate_required(@req_fields)
    |> update_change(:base_url, &trim_url/1)
    |> update_change(:grafana_url, &trim_url/1)
    |> validate_number(:suspend_min, greater_than: 0, less_than_or_equal_to: 90)
    |> validate_number(:suspend_after_idle_min, greater_than: 0, less_than_or_equal_to: 60)
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
