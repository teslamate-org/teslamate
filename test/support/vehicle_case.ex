defmodule TeslaMate.VehicleCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias TeslaMate.Vehicles.Vehicle
      alias TeslaApi.Vehicle.State

      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      def start_vehicle(name, vehicle, events, opts \\ []) when length(events) > 0 do
        log_name = :"log_#{name}"
        api_name = :"api_#{name}"

        {:ok, _pid} = start_supervised({LogMock, name: log_name, pid: self()})
        {:ok, _pid} = start_supervised({ApiMock, name: api_name, events: events, pid: self()})

        {:ok, _pid} =
          start_supervised(
            {Vehicle,
             [name: name, vehicle: vehicle, log: {LogMock, log_name}, api: {ApiMock, api_name}] ++
               opts}
          )

        :ok
      end

      def vehicle_full(opts) do
        charge_state = Keyword.get(opts, :charge_state, %{})
        drive_state = Keyword.get(opts, :drive_state, %{})
        climate_state = Keyword.get(opts, :climate_state, %{})
        vehicle_state = Keyword.get(opts, :vehicle_state, %{})

        %TeslaApi.Vehicle{
          state: "online",
          charge_state: struct(State.Charge, charge_state),
          drive_state: struct(State.Drive, drive_state),
          climate_state: struct(State.Climate, climate_state),
          vehicle_state: struct(State.VehicleState, vehicle_state)
        }
      end
    end
  end
end
