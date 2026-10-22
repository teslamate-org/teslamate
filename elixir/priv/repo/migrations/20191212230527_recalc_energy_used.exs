defmodule TeslaMate.Repo.Migrations.RecalcEnergyUsed.CustomExpressions do
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

  defmacro duration_min(a, b) do
    quote do
      fragment(
        "(EXTRACT(EPOCH FROM (?::timestamp - ?::timestamp)) / 60)::integer",
        unquote(a),
        unquote(b)
      )
    end
  end

  defmacro nullif(a, b) do
    quote do
      fragment("NULLIF(?, ?)", unquote(a), unquote(b))
    end
  end

  defmacro round(v, s) do
    quote do
      fragment("ROUND((?)::numeric, ?)::float8", unquote(v), unquote(s))
    end
  end
end

defmodule TeslaMate.Repo.Migrations.RecalcEnergyUsed do
  use Ecto.Migration

  require Logger

  defmodule Charge do
    use Ecto.Schema
    import Ecto.Changeset

    alias ChargingProcess

    schema "charges" do
      field(:date, :utc_datetime_usec)
      field(:battery_level, :integer)
      field(:charge_energy_added, :float)
      field(:charger_actual_current, :integer)
      field(:charger_phases, :integer, default: 1)
      field(:charger_power, :float)
      field(:charger_voltage, :integer)
      field(:ideal_battery_range_km, :float)
      field(:rated_battery_range_km, :float)
      field(:outside_temp, :float)

      belongs_to(:charging_process, ChargingProcess)
    end
  end

  defmodule ChargingProcess do
    use Ecto.Schema
    import Ecto.Changeset

    alias TeslaMate.Log.Charge

    schema "charging_processes" do
      field(:start_date, :utc_datetime_usec)
      field(:end_date, :utc_datetime_usec)
      field(:charge_energy_added, :float)
      field(:charge_energy_used, :float)
      field(:start_ideal_range_km, :float)
      field(:end_ideal_range_km, :float)
      field(:start_rated_range_km, :float)
      field(:end_rated_range_km, :float)
      field(:start_battery_level, :integer)
      field(:end_battery_level, :integer)
      field(:duration_min, :integer)
      field(:outside_temp_avg, :float)

      has_many(:charges, Charge)
    end

    @doc false
    def changeset(charging_state, attrs) do
      charging_state
      |> cast(attrs, [
        :start_date,
        :end_date,
        :charge_energy_added,
        :charge_energy_used,
        :start_ideal_range_km,
        :end_ideal_range_km,
        :start_rated_range_km,
        :end_rated_range_km,
        :start_battery_level,
        :end_battery_level,
        :duration_min,
        :outside_temp_avg
      ])
      |> validate_required([:start_date])
      |> validate_number(:charge_energy_added, greater_than_or_equal_to: 0)
      |> validate_number(:charge_energy_used, greater_than_or_equal_to: 0)
    end
  end

  import Ecto.Query
  import __MODULE__.CustomExpressions

  alias TeslaMate.Repo

  def up do
    ChargingProcess
    |> Repo.all()
    |> Enum.each(&complete_charging_process/1)
  end

  def down do
    :ok
  end

  defp complete_charging_process(%ChargingProcess{} = charging_process) do
    stats =
      from(c in Charge,
        select: %{
          start_ideal_range_km: first_value(c.ideal_battery_range_km) |> over(:w),
          end_ideal_range_km: last_value(c.ideal_battery_range_km) |> over(:w),
          start_rated_range_km: first_value(c.rated_battery_range_km) |> over(:w),
          end_rated_range_km: last_value(c.rated_battery_range_km) |> over(:w),
          start_battery_level: first_value(c.battery_level) |> over(:w),
          end_battery_level: last_value(c.battery_level) |> over(:w),
          outside_temp_avg: avg(c.outside_temp) |> over(:w),
          charge_energy_added:
            (last_value(c.charge_energy_added) |> over(:w)) -
              (first_value(c.charge_energy_added) |> over(:w)),
          duration_min:
            duration_min(last_value(c.date) |> over(:w), first_value(c.date) |> over(:w)),
          detected_end_date: last_value(c.date) |> over(:w)
        },
        windows: [
          w: [
            order_by:
              fragment("? RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING", c.date)
          ]
        ],
        where: [charging_process_id: ^charging_process.id],
        limit: 1
      )
      |> Repo.one() || %{detected_end_date: nil}

    charge_energy_used = calculate_energy_used(charging_process)

    attrs =
      stats
      |> Map.put(:end_date, charging_process.end_date || stats.detected_end_date)
      |> Map.put(:charge_energy_used, charge_energy_used)
      |> Map.update(:charge_energy_added, nil, &if(&1 < 0, do: nil, else: &1))

    charging_process |> ChargingProcess.changeset(attrs) |> Repo.update()
  end

  defp calculate_energy_used(%ChargingProcess{id: id} = charging_process) do
    phases = determine_phases(charging_process)

    query =
      from(c in Charge,
        join: p in ChargingProcess,
        on: [id: c.charging_process_id],
        select: %{
          energy_used:
            c_if is_nil(c.charger_phases) do
              c.charger_power
            else
              c.charger_actual_current * c.charger_voltage * type(^phases, :float) / 1000.0
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

  defp determine_phases(%ChargingProcess{id: id}) do
    from(c in Charge,
      join: p in ChargingProcess,
      on: [id: c.charging_process_id],
      select: {
        avg(c.charger_power * 1000 / nullif(c.charger_actual_current * c.charger_voltage, 0)),
        type(avg(c.charger_phases), :integer),
        type(avg(c.charger_voltage), :float),
        count()
      },
      group_by: c.charging_process_id,
      where: c.charging_process_id == ^id
    )
    |> Repo.one()
    |> case do
      {p, r, v, n} when not is_nil(p) and p > 0 and n > 15 ->
        cond do
          r == round(p) ->
            r

          r == 3 and abs(p / :math.sqrt(r) - 1) <= 0.1 ->
            Logger.info("Voltage correction: #{round(v)}V -> #{round(v / :math.sqrt(r))}V")
            :math.sqrt(r)

          abs(round(p) - p) <= 0.3 ->
            Logger.info("Phase correction: #{r} -> #{round(p)}")
            round(p)

          true ->
            nil
        end

      _ ->
        nil
    end
  end
end
