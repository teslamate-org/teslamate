defmodule TeslaMate.Repo.Migrations.FixIncompleteChargingProcessesV3 do
  use Ecto.Migration

  # alias TeslaMate.Log.{ChargingProcess, Charge}
  # alias TeslaMate.Repo

  # import Ecto.Query

  def up do
    # incomplete_charging_processes =
    #   ChargingProcess
    #   |> select([c], c.id)
    #   |> where([c], is_nil(c.end_date))
    #   |> Repo.all()

    # for id <- incomplete_charging_processes do
    #   {:ok, cproc} = TeslaMate.Log.complete_charging_process(id)

    #   %{end_date: end_date} =
    #     Charge
    #     |> select([c], %{end_date: max(c.date)})
    #     |> where(charging_process_id: ^id)
    #     |> Repo.one()

    #   {:ok, _} =
    #     cproc
    #     |> ChargingProcess.changeset(%{end_date: end_date})
    #     |> Repo.update()
    # end
    :ok
  end

  def down do
    :ok
  end
end
