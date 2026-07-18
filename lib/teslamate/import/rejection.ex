defmodule TeslaMate.Import.Rejection do
  @moduledoc false

  use Ecto.Schema

  alias TeslaMate.Import.Run

  schema "import_rejections" do
    field :file_name, :string
    field :file_fingerprint, :string
    field :row, :integer

    field :reason, Ecto.Enum,
      values: [
        :invalid_fields,
        :parse_error,
        :invalid_date,
        :ambiguous_local_time,
        :nonexistent_local_time,
        :invalid_timezone,
        :column_count_mismatch
      ]

    field :fields, {:array, :string}, default: []

    belongs_to :run, Run

    timestamps(type: :utc_datetime_usec)
  end
end
