defmodule TeslaMate.Repair do
  use GenServer

  require Logger
  import Ecto.Query

  alias TeslaMate.Log.{Drive, Position, ChargingProcess}
  alias TeslaMate.Locations.Address
  alias TeslaMate.{Repo, Locations}

  defmodule State do
    defstruct [:limit]
  end

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__, fullsweep_after: 10)
  end

  def trigger_run do
    GenServer.cast(__MODULE__, :repair)
  end

  @impl true
  def init(opts) do
    {:ok, _ref} =
      opts
      |> Keyword.get_lazy(:interval, fn -> :timer.hours(1) end)
      |> :timer.send_interval(self(), :repair)

    :ok = trigger_run()

    {:ok, %State{limit: Keyword.get(opts, :limit, 5000)}}
  end

  ## Repair

  @impl true
  def handle_cast(:repair, %State{limit: limit} = state) do
    from(d in Drive,
      join: sp in assoc(d, :start_position),
      join: ep in assoc(d, :end_position),
      select: [
        :id,
        :car_id,
        :start_date,
        {:start_position, [:id, :latitude, :longitude]},
        {:end_position, [:id, :latitude, :longitude]}
      ],
      where:
        (is_nil(d.start_address_id) or is_nil(d.end_address_id)) and
          (not is_nil(d.start_position_id) and not is_nil(d.end_position_id)),
      order_by: [desc: :id],
      preload: [start_position: sp, end_position: ep],
      limit: ^limit
    )
    |> Repo.all()
    |> repair()

    from(c in ChargingProcess,
      join: p in assoc(c, :position),
      select: [:id, :car_id, :start_date, {:position, [:id, :latitude, :longitude]}],
      where: is_nil(c.address_id) and not is_nil(c.position_id),
      order_by: [desc: :id],
      preload: [position: p],
      limit: ^limit
    )
    |> Repo.all()
    |> repair()

    {:noreply, state}
  end

  @impl true
  def handle_info(:repair, state) do
    :ok = trigger_run()
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg, pretty: true)}")
    {:noreply, state}
  end

  # Private

  defp repair([]), do: :ok

  defp repair([entity | rest]) do
    case entity do
      %Drive{} = drive ->
        Logger.info("Repairing drive ##{drive.id} ...")

        drive
        |> Drive.changeset(%{
          start_address_id: get_address_id(drive.start_position),
          end_address_id: get_address_id(drive.end_position)
        })
        |> Repo.update()

      %ChargingProcess{} = charge ->
        Logger.info("Repairing charging process ##{charge.id} ...")

        charge
        |> ChargingProcess.changeset(%{address_id: get_address_id(charge.position)})
        |> Repo.update()
    end
    |> case do
      {:error, reason} -> Logger.warning("Failure: #{inspect(reason, pretty: true)}")
      {:ok, _entity} -> Logger.info("OK")
    end

    repair(rest)
  end

  defp get_address_id(nil), do: nil

  defp get_address_id(%Position{} = position) do
    case :fuse.ask(:addr_fuse, :sync) do
      :ok ->
        Process.sleep(1500)

        case Locations.find_address(position) do
          {:error, {:geocoding_failed, reason}} ->
            Logger.warning("Geocoding failed: #{reason}")
            nil

          {:error, reason} ->
            :fuse.melt(:addr_fuse)
            Logger.warning("Address not found: #{inspect(reason)}")
            nil

          {:ok, %Address{display_name: _name, id: id}} ->
            id
        end

      :blown ->
        nil

      {:error, :not_found} ->
        Logger.debug("Installing circuit-breaker :addr_fuse ...")

        :fuse.install(
          :addr_fuse,
          {{:standard, 5, :timer.minutes(3)}, {:reset, :timer.minutes(15)}}
        )

        get_address_id(position)
    end
  end
end
