defmodule TeslaMate.Repo.Migrations.CarSettings do
  use Ecto.Migration

  defmodule Settings do
    use Ecto.Schema
    import Ecto.Changeset

    schema "settings" do
      field(:suspend_min, :integer)
      field(:suspend_after_idle_min, :integer)
      field(:req_no_shift_state_reading, :boolean)
      field(:req_no_temp_reading, :boolean)
      field(:req_not_unlocked, :boolean)
    end
  end

  defmodule CarSettings do
    use Ecto.Schema
    import Ecto.Changeset

    schema "car_settings" do
      field(:suspend_min, :integer)
      field(:suspend_after_idle_min, :integer)
      field(:req_no_shift_state_reading, :boolean)
      field(:req_no_temp_reading, :boolean)
      field(:req_not_unlocked, :boolean)
    end

    @all_fields [
      :suspend_min,
      :suspend_after_idle_min,
      :req_no_shift_state_reading,
      :req_no_temp_reading,
      :req_not_unlocked
    ]

    def changeset(settings, attrs) do
      settings
      |> cast(attrs, @all_fields)
      |> validate_required(@all_fields)
      |> validate_number(:suspend_min, greater_than: 0, less_than_or_equal_to: 90)
      |> validate_number(:suspend_after_idle_min, greater_than: 0, less_than_or_equal_to: 60)
    end
  end

  defmodule Car do
    use Ecto.Schema
    import Ecto.Changeset

    schema "cars" do
      belongs_to(:settings, CarSettings)
    end

    @doc false
    def changeset(car, attrs) do
      car
      |> cast(attrs, [])
      |> cast_assoc(:settings, with: &CarSettings.changeset/2, required: true)
    end
  end

  alias TeslaMate.Repo

  def up do
    create table(:car_settings) do
      add(:suspend_min, :integer, default: 21, null: false)
      add(:suspend_after_idle_min, :integer, default: 15, null: false)

      add(:req_no_shift_state_reading, :boolean, null: false, default: false)
      add(:req_no_temp_reading, :boolean, null: false, default: false)
      add(:req_not_unlocked, :boolean, null: false, default: true)
    end

    alter table(:cars) do
      add(:settings_id, references(:car_settings), null: true)
    end

    flush()

    [settings] = Repo.all(Settings)

    for car <- Repo.all(Car) do
      car
      |> Repo.preload(:settings)
      |> Car.changeset(%{settings: Map.from_struct(settings)})
      |> Repo.update!()
    end

    drop(constraint(:cars, "cars_settings_id_fkey"))

    alter table(:cars) do
      modify(:settings_id, references(:car_settings), null: false)
    end

    create(unique_index(:cars, :settings_id))

    alter table(:settings) do
      remove(:suspend_min, :integer)
      remove(:suspend_after_idle_min)

      remove(:req_no_shift_state_reading)
      remove(:req_no_temp_reading)
      remove(:req_not_unlocked)
    end
  end

  def down do
    alter table(:cars) do
      remove(:settings_id)
    end

    drop(table(:car_settings))

    alter table(:settings) do
      add(:suspend_min, :integer, default: 21, null: false)
      add(:suspend_after_idle_min, :integer, default: 15, null: false)

      add(:req_no_shift_state_reading, :boolean, null: false, default: false)
      add(:req_no_temp_reading, :boolean, null: false, default: false)
      add(:req_not_unlocked, :boolean, null: false, default: true)
    end
  end
end
