defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriberTest do
  use TeslaMate.DataCase, async: true

  import TestHelper, only: [drain_discovery_configs: 0]

  alias TeslaMate.Mqtt.PubSub.VehicleSubscriber
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.Car

  @migration_delay 10

  defmodule BlockingPublisher do
    def publish(test_pid, topic, message, opts) do
      send(test_pid, {__MODULE__, {:publish, topic, message, opts}, self()})

      if String.ends_with?(topic, "/healthy") and message == "" do
        receive do
          :continue -> :ok
        end
      else
        :ok
      end
    end
  end

  defp start_subscriber(
         name,
         car_id,
         namespace \\ nil,
         publisher_responses \\ %{},
         extra_opts \\ []
       ) do
    publisher_name = :"mqtt_publisher_#{name}"
    vehicles_name = :"vehicles_#{name}"

    {:ok, _pid} =
      start_supervised(
        {MqttPublisherMock, name: publisher_name, pid: self(), responses: publisher_responses}
      )

    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})

    start_supervised(
      {VehicleSubscriber,
       [
         name: name,
         car_id: car_id,
         namespace: namespace,
         migration_delay: @migration_delay,
         deps_publisher: {MqttPublisherMock, publisher_name},
         deps_vehicles: {VehiclesMock, vehicles_name}
       ]
       |> Keyword.merge(extra_opts)}
    )
  end

  defp assert_discovery_retry(pid, expected_delay) do
    state = :sys.get_state(pid)

    assert state.discovery_retry_delay == expected_delay
    assert is_reference(state.discovery_retry_timer)
    assert is_reference(state.discovery_retry_token)
    assert is_integer(Process.read_timer(state.discovery_retry_timer))

    state
  end

  defp fire_discovery_retry(pid) do
    state = :sys.get_state(pid)

    assert is_reference(state.discovery_retry_timer)
    assert is_reference(state.discovery_retry_token)
    assert is_integer(Process.cancel_timer(state.discovery_retry_timer))

    send(pid, {:retry_discovery, state.discovery_retry_token})
  end

  test "starts before retained topic cleanup completes", %{test: name} do
    vehicles_name = :"vehicles_#{name}"
    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})

    test_pid = self()

    task =
      Task.async(fn ->
        VehicleSubscriber.start_link(
          car_id: 0,
          namespace: nil,
          deps_publisher: {BlockingPublisher, test_pid},
          deps_vehicles: {VehiclesMock, vehicles_name}
        )
      end)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    assert {:ok, {:ok, subscriber_pid}} = Task.yield(task, 2_000)

    send(subscriber_pid, %Summary{healthy: true})
    send(subscriber_pid, :continue)

    assert_receive {BlockingPublisher, {:publish, "teslamate/cars/0/healthy", message, opts},
                    from_pid}

    assert {message, opts, from_pid} == {"", [retain: true, qos: 1], subscriber_pid}

    assert_receive {BlockingPublisher,
                    {:publish, "teslamate/cars/0/healthy", "true", [retain: false, qos: 1]},
                    _publisher_pid}

    :ok = GenServer.stop(subscriber_pid, :normal, 1_000)
  end

  @tag :capture_log
  test "logs retained cleanup publish failures", %{test: name} do
    topic = "teslamate/cars/0/healthy"

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} = start_subscriber(name, 0, nil, %{topic => [{:error, :disconnected}]})

        assert_receive {MqttPublisherMock, {:publish, ^topic, "", [retain: true, qos: 1]}}

        send(pid, %Summary{healthy: true})
        assert_receive {MqttPublisherMock, {:publish, ^topic, "true", [retain: false, qos: 1]}}
      end)

    assert log =~ "MQTT retained cleanup failed for #{topic}: {:error, :disconnected}"
  end

  test "publishes vehicle data", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    drain_discovery_configs()

    summary = %Summary{
      healthy: true,
      display_name: "Foo",
      odometer: 42_000,
      windows_open: true,
      driver_front_window_open: true,
      driver_rear_window_open: false,
      passenger_front_window_open: false,
      passenger_rear_window_open: true,
      doors_open: true,
      shift_state: "D",
      state: :online,
      since: DateTime.utc_now(),
      latitude: 37.889602,
      longitude: 41.129182,
      power: -9,
      speed: 40,
      heading: 340,
      outside_temp: 15,
      inside_temp: 20.0,
      locked: true,
      sentry_mode: false,
      plugged_in: false,
      version: "2019.42",
      update_available: false,
      update_version: "2019.43",
      is_preconditioning: true,
      is_user_present: false,
      is_climate_on: true,
      geofence: %GeoFence{id: 0, name: "Home", latitude: 0.0, longitude: 0.0, radius: 20},
      model: "S",
      trim_badging: "P100D",
      exterior_color: "White",
      spoiler_type: "None",
      wheel_type: "AeroTurbine19",
      frunk_open: true,
      trunk_open: false,
      elevation: 100,
      sun_roof_state: "open",
      sun_roof_installed: true,
      sun_roof_percent_open: 80
    }

    send(pid, summary)

    for {key, val} <- Map.from_struct(summary),
        not is_nil(val) and key not in [:since, :geofence] do
      topic = "teslamate/cars/0/#{key}"
      data = to_string(val)
      retain = key not in [:healthy]
      assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: ^retain, qos: 1]}}
    end

    iso_time = DateTime.to_iso8601(summary.since)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/since", ^iso_time, [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/geofence", "Home", [retain: true, qos: 1]}}

    for key <- [
          :charge_energy_added,
          :charger_actual_current,
          :charger_phases,
          :charger_power,
          :charger_voltage,
          :scheduled_charging_start_time,
          :time_to_full_charge
        ] do
      topic = "teslamate/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "", [retain: true, qos: 1]}}
    end

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/location", data, [retain: true, qos: 1]}}

    assert Jason.decode!(data) == %{
             "latitude" => 37.889602,
             "longitude" => 41.129182
           }

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/software_update", data, [retain: true, qos: 1]}}

    assert Jason.decode!(data) == %{
             "installed_version" => "2019.42",
             "latest_version" => "2019.42"
           }

    # Published as nil
    for key <- [
          :active_route_destination,
          :active_route_longitude,
          :active_route_latitude
        ] do
      topic = "teslamate/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "nil", [retain: true, qos: 1]}}
    end

    # Published as nil
    for key <- [
          :active_route
        ] do
      topic = "teslamate/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, data, [retain: true, qos: 1]}}
      assert Jason.decode!(data) == %{"error" => "No active route available"}
    end

    # The healthy topic is published with retain: true to clean up previously retained messages
    # See: https://github.com/teslamate-org/teslamate/pull/4817
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/healthy", "", [retain: true, qos: 1]}}

    refute_receive _
  end

  test "publishes available software update state", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    drain_discovery_configs()

    send(pid, %Summary{
      version: "2026.14.1",
      update_available: true,
      update_version: "2026.20.1"
    })

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/software_update", data, [retain: true, qos: 1]}}

    assert Jason.decode!(data) == %{
             "installed_version" => "2026.14.1",
             "latest_version" => "2026.20.1"
           }
  end

  test "publishes charging data", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    drain_discovery_configs()

    summary = %Summary{
      plugged_in: false,
      battery_level: 60.0,
      usable_battery_level: 59,
      charge_energy_added: 25,
      charge_limit_soc: 90,
      charge_port_door_open: false,
      charger_actual_current: 42,
      charger_phases: 3,
      charger_power: 50,
      charger_voltage: 16,
      est_battery_range_km: 220.05,
      ideal_battery_range_km: 230.52,
      rated_battery_range_km: 230.52,
      scheduled_charging_start_time: DateTime.utc_now() |> DateTime.add(60 * 60 * 10, :second),
      time_to_full_charge: 2.5
    }

    send(pid, summary)

    # The healthy topic is published with retain: true to clean up previously retained messages
    # See: https://github.com/teslamate-org/teslamate/pull/4817
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/healthy", "", [retain: true, qos: 1]}}

    for {key, val} <- Map.from_struct(summary),
        not is_nil(val) and key != :scheduled_charging_start_time do
      topic = "teslamate/cars/0/#{key}"
      data = to_string(val)
      retain = key not in [:healthy]
      assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: ^retain, qos: 1]}}
    end

    # Formatted dates
    iso_time = DateTime.to_iso8601(summary.scheduled_charging_start_time)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/scheduled_charging_start_time", ^iso_time,
                     [retain: true, qos: 1]}}

    # Always published
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/shift_state", "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/geofence", "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/trim_badging", "", [retain: true, qos: 1]}}

    # Published as nil
    for key <- [
          :active_route_destination,
          :active_route_longitude,
          :active_route_latitude
        ] do
      topic = "teslamate/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "nil", [retain: true, qos: 1]}}
    end

    # Published as nil
    for key <- [
          :active_route
        ] do
      topic = "teslamate/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, data, [retain: true, qos: 1]}}
      assert Jason.decode!(data) == %{"error" => "No active route available"}
    end

    # The healthy topic is always published without retain to prevent stale status
    # See: https://github.com/teslamate-org/teslamate/pull/4817
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/healthy", "", [retain: false, qos: 1]}}

    refute_receive _
  end

  test "publishes geofence only if it has changed", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    geofence = %GeoFence{id: 0, name: "Home", latitude: 0.0, longitude: 0.0, radius: 20}
    other_geofence = %GeoFence{id: 0, name: "Work", latitude: 0.0, longitude: 0.0, radius: 20}

    # Send geofence
    send(pid, %Summary{geofence: geofence, version: "1"})
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/geofence", "Home", _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "1", _}}

    # Send geofence again and expect no message
    send(pid, %Summary{geofence: geofence, version: "2"})
    refute_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/geofence", _, _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "2", _}}

    # Send another geofence
    send(pid, %Summary{geofence: other_geofence, version: "3"})
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/geofence", "Work", _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "3", _}}
  end

  @tag :capture_log
  test "retries failed values until they are published successfully", %{test: name} do
    display_name_topic = "teslamate/cars/0/display_name"
    shift_state_topic = "teslamate/cars/0/shift_state"

    responses = %{
      display_name_topic => [{:error, :disconnected}, :ok],
      shift_state_topic => [{:error, :disconnected}, :ok]
    }

    {:ok, pid} = start_subscriber(name, 0, nil, responses)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    summary = %Summary{display_name: "Foo", version: "1"}
    send(pid, summary)

    assert_receive {MqttPublisherMock, {:publish, ^display_name_topic, "Foo", _}}
    assert_receive {MqttPublisherMock, {:publish, ^shift_state_topic, "", _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "1", _}}

    send(pid, summary)

    assert_receive {MqttPublisherMock, {:publish, ^display_name_topic, "Foo", _}}
    assert_receive {MqttPublisherMock, {:publish, ^shift_state_topic, "", _}}
    refute_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "1", _}}

    send(pid, summary)

    refute_receive {MqttPublisherMock, {:publish, ^display_name_topic, "Foo", _}}
    refute_receive {MqttPublisherMock, {:publish, ^shift_state_topic, "", _}}
  end

  test "allows namespaces", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0, "account_0")

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    drain_discovery_configs()

    summary = %Summary{
      display_name: "Foo",
      state: :online
    }

    send(pid, summary)

    # The healthy topic is published with retain: true to clean up previously retained messages
    # See: https://github.com/teslamate-org/teslamate/pull/4817
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/account_0/cars/0/healthy", "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/account_0/cars/0/display_name", "Foo",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/account_0/cars/0/state", "online",
                     [retain: true, qos: 1]}}

    # Always published
    for key <- [
          :charge_energy_added,
          :charger_actual_current,
          :charger_phases,
          :charger_power,
          :charger_voltage,
          :scheduled_charging_start_time,
          :time_to_full_charge,
          :shift_state,
          :geofence,
          :trim_badging
        ] do
      topic = "teslamate/account_0/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "", [retain: true, qos: 1]}}
    end

    # Published as nil
    for key <- [
          :active_route_destination,
          :active_route_longitude,
          :active_route_latitude
        ] do
      topic = "teslamate/account_0/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "nil", [retain: true, qos: 1]}}
    end

    # Published as nil
    for key <- [
          :active_route
        ] do
      topic = "teslamate/account_0/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, data, [retain: true, qos: 1]}}
      assert Jason.decode!(data) == %{"error" => "No active route available"}
    end

    # The healthy topic is always published without retain to prevent stale status
    # See: https://github.com/teslamate-org/teslamate/pull/4817
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/account_0/cars/0/healthy", "", [retain: false, qos: 1]}}

    refute_receive _
  end

  test "publishes Home Assistant discovery config when device metadata changes", %{test: name} do
    {:ok, pid} =
      start_subscriber(name, 0, nil, %{},
        discovery: true,
        discovery_base_url: "https://teslamate.example.com/"
      )

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    summary = %Summary{
      healthy: true,
      display_name: "Foo",
      model: "3",
      trim_badging: "74D",
      exterior_color: "DeepBlue",
      wheel_type: "AeroTurbine19",
      state: :online,
      car: %Car{name: "Foo", marketing_name: "LR AWD"}
    }

    send(pid, summary)

    # The discovery config message is emitted synchronously on the first
    # summary.
    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", payload,
                     [retain: true, qos: 1]}},
                   500

    decoded = Jason.decode!(payload)
    assert Map.has_key?(decoded, "device")
    assert Map.has_key?(decoded, "components")
    assert Map.has_key?(decoded, "origin")

    assert decoded["device"]["model"] ==
             ~s|Model 3 LR AWD (Deep Blue, Aero Turbine 19" Wheels)|

    drain_discovery_configs()

    send(pid, %Summary{summary | speed: 42})

    # Changes unrelated to device metadata do not republish discovery.
    refute_receive {MqttPublisherMock,
                    {:publish, "homeassistant/" <> _, _, [retain: true, qos: 1]}}

    summary = %Summary{summary | exterior_color: "PearlWhiteMultiCoat"}
    send(pid, summary)

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", payload,
                     [retain: true, qos: 1]}},
                   500

    assert Jason.decode!(payload)["device"]["model"] ==
             ~s|Model 3 LR AWD (Pearl White Multi Coat, Aero Turbine 19" Wheels)|

    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}

    send(pid, %Summary{summary | sun_roof_installed: false})
    :sys.get_state(pid)

    # nil and false both omit the sunroof detail, so the rendered device is unchanged.
    refute_receive {MqttPublisherMock,
                    {:publish, "homeassistant/" <> _, _, [retain: true, qos: 1]}}

    send(pid, %Summary{summary | update_available: true, update_version: "2026.20.1"})
    :sys.get_state(pid)

    # Software update state changes do not require discovery to be republished.
    refute_receive {MqttPublisherMock,
                    {:publish, "homeassistant/" <> _, _, [retain: true, qos: 1]}}

    car = %{summary.car | marketing_name: "Performance"}
    send(pid, %Summary{summary | car: car})

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", payload,
                     [retain: true, qos: 1]}},
                   500

    assert Jason.decode!(payload)["device"]["model"] ==
             ~s|Model 3 Performance (Pearl White Multi Coat, Aero Turbine 19" Wheels)|

    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}

    send(pid, %Summary{summary | sun_roof_installed: true})

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", payload,
                     [retain: true, qos: 1]}},
                   500

    assert Jason.decode!(payload)["device"]["model"] ==
             ~s|Model 3 LR AWD (Pearl White Multi Coat, Aero Turbine 19" Wheels, Sunroof)|

    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}

    send(pid, %Summary{summary | sun_roof_installed: true, version: "2026.26.1"})

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", payload,
                     [retain: true, qos: 1]}},
                   500

    assert Jason.decode!(payload)["device"]["sw_version"] == "2026.26.1"
    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}
  end

  @tag :capture_log
  test "backs off failed discovery publishes and retries the latest metadata", %{test: name} do
    topic = "homeassistant/device/teslamate_0/config"
    error = {:error, :disconnected}
    responses = %{topic => List.duplicate(error, 7) ++ [:ok, :ok, error]}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} = start_subscriber(name, 0, nil, responses, discovery: true)

        assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

        summary = %Summary{healthy: true, display_name: "Foo", model: "3", state: :online}
        send(pid, summary)

        assert_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}

        state = assert_discovery_retry(pid, :timer.seconds(5))
        assert state.discovery_pending_summary == summary
        assert state.discovery_pending_device.model == "Model 3"

        send(pid, %Summary{summary | version: "2026.1"})
        latest = %Summary{summary | version: "2026.2"}
        send(pid, latest)

        state = :sys.get_state(pid)
        assert state.discovery_pending_summary == latest
        assert state.discovery_pending_device.sw_version == "2026.2"
        assert state.discovery_retry_delay == :timer.seconds(5)

        refute_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}

        for expected_delay <- [10, 20, 40, 80, 160, 300] do
          fire_discovery_retry(pid)

          assert_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}

          assert_discovery_retry(pid, :timer.seconds(expected_delay))
        end

        fire_discovery_retry(pid)

        assert_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}

        state = :sys.get_state(pid)
        assert state.discovery_device.sw_version == "2026.2"
        assert state.discovery_pending_summary == nil
        assert state.discovery_pending_device == nil
        assert state.discovery_retry_delay == nil
        assert state.discovery_retry_timer == nil
        assert state.discovery_retry_token == nil

        drain_discovery_configs()

        send(pid, %Summary{latest | speed: 42})
        :sys.get_state(pid)
        refute_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}

        send(pid, %Summary{latest | version: "2026.3"})
        assert_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}
        assert_discovery_retry(pid, :timer.seconds(5))
        refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}

        fire_discovery_retry(pid)
        assert_receive {MqttPublisherMock, {:publish, ^topic, _payload, _opts}}
        refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}

        state = :sys.get_state(pid)
        assert state.discovery_device.sw_version == "2026.3"
        assert state.discovery_retry_delay == nil
        assert state.discovery_retry_timer == nil
      end)

    assert length(Regex.scan(~r/MQTT HA discovery publishing failed/, log)) == 8
    assert log =~ "retrying in 5s"
    assert log =~ "retrying in 300s"
  end

  @tag :capture_log
  test "retries Home Assistant discovery after a publishing failure", %{test: name} do
    legacy_topic = "homeassistant/sensor/teslamate_0/display_name/config"

    {:ok, pid} =
      start_subscriber(name, 0, nil, %{legacy_topic => [{:error, :disconnected}]},
        discovery: true
      )

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    summary = %Summary{healthy: true, display_name: "Foo", model: "3", state: :online}
    send(pid, summary)

    assert_receive {MqttPublisherMock,
                    {:publish, ^legacy_topic, _migration_payload, [retain: true, qos: 1]}}

    refute_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", _, _}}

    assert_discovery_retry(pid, :timer.seconds(5))
    fire_discovery_retry(pid)

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", _payload,
                     [retain: true, qos: 1]}},
                   500

    drain_discovery_configs()
  end

  test "clears discovery configs when discovery is disabled", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    # Retained discovery configs are cleared on init so entities are removed
    # from Home Assistant when discovery is disabled.
    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", "",
                     [retain: true, qos: 1]}}

    drain_discovery_configs()

    send(pid, %Summary{healthy: true, display_name: "Foo", state: :online})

    # No discovery config should be published when discovery is disabled
    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}
  end

  test "starts when the namespace option is absent (MQTT_NAMESPACE unset)", %{test: name} do
    publisher_name = :"mqtt_publisher_#{name}"
    vehicles_name = :"vehicles_#{name}"

    {:ok, _pid} =
      start_supervised({MqttPublisherMock, name: publisher_name, pid: self(), responses: %{}})

    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})

    # Mqtt.init drops nil options before starting PubSub, so subscribers must
    # start without a :namespace key (regression: KeyError boot crash in 4.1.0)
    {:ok, _pid} =
      start_supervised(
        {VehicleSubscriber,
         [
           name: name,
           car_id: 0,
           discovery: false,
           deps_publisher: {MqttPublisherMock, publisher_name},
           deps_vehicles: {VehiclesMock, vehicles_name}
         ]}
      )

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}
  end
end
