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

      def online_event(opts \\ []) do
        drive_state =
          Keyword.get(opts, :drive_state, %{
            timestamp: 0,
            latitude: 0.0,
            longitude: 0.0
          })

        charge_state = Keyword.get(opts, :charge_state, %{})
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

      def drive_event(ts, shift_state, speed_mph) do
        online_event(
          drive_state: %{
            timestamp: ts,
            latitude: 0.1,
            longitude: 0.1,
            shift_state: shift_state,
            speed: speed_mph
          }
        )
      end

      def charging_event(ts, charging_state, charge_energy_added) do
        online_event(
          charge_state: %{
            timestamp: ts,
            charging_state: charging_state,
            charge_energy_added: charge_energy_added
          },
          drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0}
        )
      end
    end
  end
end
