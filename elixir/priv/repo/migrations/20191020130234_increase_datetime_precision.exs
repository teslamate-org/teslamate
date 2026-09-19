defmodule TeslaMate.Repo.Migrations.IncreaseDatetimePrecision do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      modify(:start_date, :utc_datetime_usec, from: :utc_datetime)
      modify(:end_date, :utc_datetime_usec, from: :utc_datetime)
    end

    alter table(:drives) do
      modify(:start_date, :utc_datetime_usec, from: :utc_datetime)
      modify(:end_date, :utc_datetime_usec, from: :utc_datetime)
    end

    alter table(:states) do
      modify(:start_date, :utc_datetime_usec, from: :utc_datetime)
      modify(:end_date, :utc_datetime_usec, from: :utc_datetime)
    end

    alter table(:updates) do
      modify(:start_date, :utc_datetime_usec, from: :utc_datetime)
      modify(:end_date, :utc_datetime_usec, from: :utc_datetime)
    end

    alter table(:charges) do
      modify(:date, :utc_datetime_usec, from: :utc_datetime)
    end

    alter table(:positions) do
      modify(:date, :utc_datetime_usec, from: :utc_datetime)
    end
  end
end
