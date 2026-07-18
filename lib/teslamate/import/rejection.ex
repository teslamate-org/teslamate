defmodule TeslaMate.Import.Rejection do
  @moduledoc false

  use Ecto.Schema

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
    field :run_id, :integer

    timestamps(type: :utc_datetime_usec)
  end
end
