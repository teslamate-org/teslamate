defmodule TeslaMate.Repair do
  use GenStateMachine

  require Logger
  import Ecto.Query

  alias TeslaMate.Log.{Drive, Position, ChargingProcess}
  alias TeslaMate.Locations.{Address, Geocoder}
  alias TeslaMate.{Repo, Locations}

  # API

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl true
  def init(_opts) do
    {:ok, _ref} = :timer.send_interval(:timer.hours(6), self(), :repair)

    {:ok, :ready, nil, {:next_event, :internal, :repair}}
  end

  ## Repair

  @impl true
  def handle_event(event, :repair, :ready, _data) when event in [:internal, :info] do
    from(d in Drive,
      where:
        (is_nil(d.start_address_id) or is_nil(d.end_address_id)) and
          (not is_nil(d.start_position_id) and not is_nil(d.end_position_id)),
      order_by: [desc: :id],
      preload: [:start_position, :end_position]
    )
    |> Repo.all()
    |> repair()

    from(c in ChargingProcess,
      where: is_nil(c.address_id) and not is_nil(c.position_id),
      order_by: [desc: :id],
      preload: [:position]
    )
    |> Repo.all()
    |> repair()

    :keep_state_and_data
  end

  def handle_event(_kind, :repair, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, {ref, _result}, _state, _data) when is_reference(ref) do
    :keep_state_and_data
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
      {:error, reason} -> Logger.warn("Failure: #{inspect(reason, pretty: true)}")
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
          {:error, reason} ->
            :fuse.melt(:addr_fuse)
            Logger.warn("Address not found: #{inspect(reason)}")
            nil

          {:ok, %Locations.Address{display_name: _name, id: id}} ->
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

  defp schedule_refresh(n), do: {:state_timeout, :timer.seconds(n), :refresh}
end
