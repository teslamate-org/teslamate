defmodule TeslaMate.Log.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :color, :string, default: "#6c757d"

    many_to_many :drives, TeslaMate.Log.Drive, join_through: TeslaMate.Log.DriveTag

    timestamps()
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a valid hex color")
    |> unique_constraint(:name)
  end
end

defimpl Phoenix.HTML.Safe, for: TeslaMate.Log.Tag do
  def to_iodata(%TeslaMate.Log.Tag{name: name, id: id}) do
    "#{name} (ID: #{id})"
  end
end