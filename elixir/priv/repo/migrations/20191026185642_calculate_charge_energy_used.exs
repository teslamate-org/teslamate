defmodule CustomExpressions do
  import Ecto.Query, warn: false

  defmacro c_if(condition, do: do_clause, else: else_clause) do
    quote do
      fragment(
        "CASE WHEN ? THEN ? ELSE ? END",
        unquote(condition),
        unquote(do_clause),
        unquote(else_clause)
      )
    end
  end
end

defmodule TeslaMate.Repo.Migrations.CalculateChargeEnergyUsed do
  use Ecto.Migration

  import Ecto.Query
  import CustomExpressions

  alias TeslaMate.Repo

  defmodule ChargingProcess do
    use Ecto.Schema
    import Ecto.Changeset

    schema "charging_processes" do
      field(:charge_energy_used, :float)
    end

    @doc false
    def changeset(charging_state, attrs) do
      charging_state
      |> cast(attrs, [:charge_energy_used])
      |> validate_number(:charge_energy_used, greater_than_or_equal_to: 0)
    end
  end

  defmodule Charge do
    use Ecto.Schema

    alias TeslaMate.Log.ChargingProcess

    schema "charges" do
      field(:date, :utc_datetime_usec)
      field(:charger_actual_current, :integer)
      field(:charger_phases, :integer, default: 1)
      field(:charger_power, :float)
      field(:charger_voltage, :integer)

      belongs_to(:charging_process, ChargingProcess)
    end
  end

  #####

  def up do
    for charge <- Repo.all(ChargingProcess) do
      {:ok, _} =
        charge
        |> ChargingProcess.changeset(%{charge_energy_used: calculate_energy_used(charge)})
        |> Repo.update()
    end
  end

  def down do
    :ok
  end

  #####

  defp calculate_energy_used(%ChargingProcess{id: id}) do
    query =
      from(c in Charge,
        select: %{
          energy_used:
            c_if is_nil(c.charger_phases) do
              c.charger_power
            else
              c.charger_actual_current * c.charger_voltage * c.charger_phases / 1000.0
            end *
              fragment(
                "EXTRACT(epoch FROM (?))",
                c.date - (lag(c.date) |> over(order_by: c.date))
              ) / 3600
        },
        where: c.charging_process_id == ^id
      )

    from(e in subquery(query),
      select: {sum(e.energy_used)},
      where: e.energy_used > 0
    )
    |> Repo.one()
    |> case do
      {charge_energy_used} -> charge_energy_used
      _ -> nil
    end
  end
end
