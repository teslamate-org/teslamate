defmodule TeslaMate.Repo.Migrations.AddIsAutoConditioningOn do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add(:is_auto_conditioning_on, :boolean)
    end
  end
end
