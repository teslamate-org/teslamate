defmodule TeslaMate.Repo.Migrations.AlignImportRunsCarIdType do
  use Ecto.Migration

  def change do
    # cars.id is smallint since 20200410112005; import_runs.car_id was created
    # as bigint. The narrowing cannot lose data: the foreign key guarantees
    # every non-NULL car_id is an existing cars.id, and Postgres raises on
    # out-of-range values instead of truncating. The foreign key itself is
    # kept and revalidated by ALTER COLUMN TYPE.
    alter table(:import_runs) do
      modify(:car_id, :smallint, from: :bigint)
    end
  end
end
