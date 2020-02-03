defmodule TeslaMate.Settings.CarSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.Car

  schema "car_settings" do
    field :sleep_mode_enabled, :boolean, default: true

    field :suspend_min, :integer, default: 21
    field :suspend_after_idle_min, :integer, default: 15

    field :req_no_shift_state_reading, :boolean, default: false
    field :req_no_temp_reading, :boolean, default: false
    field :req_not_unlocked, :boolean, default: true

    field :free_supercharging, :boolean, default: false

    has_one :car, Car, foreign_key: :settings_id
  end

  @all_fields [
    :sleep_mode_enabled,
    :suspend_min,
    :suspend_after_idle_min,
    :req_no_shift_state_reading,
    :req_no_temp_reading,
    :req_not_unlocked,
    :free_supercharging
  ]

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, @all_fields)
    |> validate_required(@all_fields)
  end
end
