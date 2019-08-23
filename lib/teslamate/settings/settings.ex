defmodule TeslaMate.Settings.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Settings.Units

  schema "settings" do
    field :unit_of_length, Units.Length
    field :unit_of_temperature, Units.Temperature

    field :suspend_min, :integer
    field :suspend_after_idle_min, :integer

    field :req_no_shift_state_reading, :boolean
    field :req_no_temp_reading, :boolean
    field :req_not_unlocked, :boolean

    timestamps()
  end

  @all_fields [
    :unit_of_length,
    :unit_of_temperature,
    :suspend_min,
    :suspend_after_idle_min,
    :req_no_shift_state_reading,
    :req_no_temp_reading,
    :req_not_unlocked
  ]

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, @all_fields)
    |> validate_required(@all_fields)
    |> validate_number(:suspend_min, greater_than: 0, less_than_or_equal_to: 90)
    |> validate_number(:suspend_after_idle_min, greater_than: 0, less_than_or_equal_to: 60)
  end
end
