defmodule TeslaMate.Log.DriveState do
  use Ecto.Schema
  import Ecto.Changeset

  alias TeslaMate.Log.Position

  schema "drive_states" do
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    field :outside_temp_avg, :float
    field :speed_max, :integer
    field :speed_min, :integer
    field :power_max, :float
    field :power_min, :float
    field :power_avg, :float

    belongs_to(:start_position, Position, foreign_key: :start_position_id)
    belongs_to(:end_position, Position, foreign_key: :end_position_id)
  end

  @doc false
  def changeset(drive_state, attrs) do
    drive_state
    |> cast(attrs, [:start_date, :end_date, :start_position_id, :end_position_id])
    |> validate_required([:start_date, :start_position_id])
    |> foreign_key_constraint(:start_position_id)
    |> foreign_key_constraint(:end_position_id)
  end
end
