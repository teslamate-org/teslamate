defmodule TeslaMate.Import.FileCheckpoint do
  @moduledoc false

  use Ecto.Schema

  schema "import_file_checkpoints" do
    field :file_name, :string
    field :file_fingerprint, :string
    field :completed_at, :utc_datetime_usec
    field :run_id, :integer

    timestamps(type: :utc_datetime_usec)
  end
end
