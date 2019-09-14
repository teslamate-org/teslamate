defmodule TeslaMate.VehicleCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias TeslaMate.Vehicles.Vehicle.Summary
      alias TeslaMate.Vehicles.Vehicle
      alias TeslaMate.Settings.Settings
      alias TeslaMate.Log.Car
      alias TeslaApi.Vehicle.State

      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      def start_vehicle(name, events, opts \\ []) when length(events) > 0 do
        log_name = :"log_#{name}"
        api_name = :"api_#{name}"
        settings_name = :"settings_#{name}"
        pubsub_name = :"pubsub_#{name}"

        {:ok, _pid} = start_supervised({LogMock, name: log_name, pid: self()})
        {:ok, _pid} = start_supervised({ApiMock, name: api_name, events: events, pid: self()})
        {:ok, _pid} = start_supervised({SettingsMock, name: settings_name, pid: self()})
        {:ok, _pid} = start_supervised({PubSubMock, name: pubsub_name, pid: self()})

        opts =
          Keyword.put_new_lazy(opts, :car, fn ->
            %Car{id: 0, eid: 0, vid: 1000}
          end)

        opts =
          case Keyword.pop(opts, :settings) do
            {nil, opts} ->
              opts

            {settings, opts} ->
              settings =
                settings
                |> Map.put_new(:req_no_shift_state_reading, false)
                |> Map.put_new(:req_no_temp_reading, false)
                |> Map.put_new(:req_not_unlocked, true)

              [{:settings, struct(Settings, settings)} | opts]
          end

        {:ok, _pid} =
          start_supervised(
            {Vehicle,
             Keyword.merge(opts,
               name: name,
               deps_log: {LogMock, log_name},
               deps_api: {ApiMock, api_name},
               deps_settings: {SettingsMock, settings_name},
               deps_pubsub: {PubSubMock, pubsub_name}
             )}
          )

        assert_receive {SettingsMock, :subscribe_to_changes}

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
        vehicle_config = Keyword.get(opts, :vehicle_config, %{car_type: "model3"})

        %TeslaApi.Vehicle{
          state: "online",
          display_name: Keyword.get(opts, :display_name),
          charge_state: struct(State.Charge, charge_state),
          drive_state: struct(State.Drive, drive_state),
          climate_state: struct(State.Climate, climate_state),
          vehicle_state: struct(State.VehicleState, vehicle_state),
          vehicle_config: struct(State.VehicleConfig, vehicle_config)
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

      defp update_event(state, version) do
        alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate

        online_event(
          vehicle_state: %{
            car_version: version,
            software_update: %SoftwareUpdate{expected_duration_sec: 2700, status: state}
          }
        )
      end
    end
  end
end
