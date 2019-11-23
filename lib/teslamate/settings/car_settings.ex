defmodule TeslaMate.Settings.CarSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.Car

  schema "car_settings" do
    field :suspend_min, :integer, default: 21
    field :suspend_after_idle_min, :integer, default: 15

    field :req_no_shift_state_reading, :boolean, default: false
    field :req_no_temp_reading, :boolean, default: false
    field :req_not_unlocked, :boolean, default: true

    has_one :car, Car, foreign_key: :settings_id
  end

  @all_fields [
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
