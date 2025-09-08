defmodule TeslaMate.Log.DriveTag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "drive_tags" do
    belongs_to :drive, TeslaMate.Log.Drive
    belongs_to :tag, TeslaMate.Log.Tag

    timestamps()
  end

  @doc false
  def changeset(drive_tag, attrs) do
    drive_tag
    |> cast(attrs, [:drive_id, :tag_id])
    |> validate_required([:drive_id, :tag_id])
    |> unique_constraint([:drive_id, :tag_id])
  end
end
