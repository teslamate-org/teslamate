defmodule TeslaMate.Import.Run do
  @moduledoc false

  use Ecto.Schema

  schema "import_runs" do
    field :source_key, :string
    field :status, Ecto.Enum, values: [:running, :complete, :abandoned]
    field :timezone, :string
    field :date_limit, :utc_datetime_usec
    field :date_limit_captured, :boolean, default: false
    field :car_id, :integer

    timestamps(type: :utc_datetime_usec)
  end
end
