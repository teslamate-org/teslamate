defmodule TeslaMate.Import.FileCheckpoint do
  @moduledoc false

  use Ecto.Schema

  alias TeslaMate.Import.Run

  schema "import_file_checkpoints" do
    field :file_name, :string
    field :file_fingerprint, :string
    field :completed_at, :utc_datetime_usec

    belongs_to :run, Run

    timestamps(type: :utc_datetime_usec)
  end
end
