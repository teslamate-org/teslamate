defmodule TeslaMate.Import.Run do
  @moduledoc false

  use Ecto.Schema

  alias TeslaMate.Log.Car

  schema "import_runs" do
    field :source_key, :string
    field :status, Ecto.Enum, values: [:running, :complete, :abandoned]
    field :timezone, :string
    field :date_limit, :utc_datetime_usec
    field :date_limit_captured, :boolean, default: false

    belongs_to :car, Car

    timestamps(type: :utc_datetime_usec)
  end
end
