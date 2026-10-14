defmodule TeslaMate.Repo.Migrations.RenameRangeEnumToPreferredRange do
  use Ecto.Migration

  def change do
    # "range" is what PostgreSQL calls its built-in range types (int4range,
    # tsrange, ...), while this enum holds the kind of range estimate (ideal or
    # rated). The new name matches its column, like unit_of_length and
    # billing_type. Renaming only changes the catalog entry; the column, its
    # default and the stored values keep pointing at the same type.
    execute(
      "ALTER TYPE range RENAME TO preferred_range",
      "ALTER TYPE preferred_range RENAME TO range"
    )
  end
end
