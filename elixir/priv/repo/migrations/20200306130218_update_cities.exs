defmodule TeslaMate.Repo.Migrations.UpdateCities do
  use Ecto.Migration

  def change do
    execute(
      """
      UPDATE addresses a
      SET city = (
        SELECT trim(BOTH '"' FROM COALESCE(
          raw -> 'address' -> 'city',
          raw -> 'address' -> 'town',
          raw -> 'address' -> 'municipality',
          raw -> 'address' -> 'village',
          raw -> 'address' -> 'hamlet',
          raw -> 'address' -> 'locality',
          raw -> 'address' -> 'croft'
        )::text)
        FROM addresses
        WHERE a.id = id
      ) WHERE
        raw -> 'address' -> 'village' IS NOT NULL OR
        raw -> 'address' -> 'hamlet' IS NOT NULL OR
        raw -> 'address' -> 'locality' IS NOT NULL OR
        raw -> 'address' -> 'croft' IS NOT NULL;
      """,
      fn -> :ok end
    )
  end
end
