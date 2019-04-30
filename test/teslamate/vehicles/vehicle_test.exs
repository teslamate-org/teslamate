defmodule TeslaMate.Vehicles.VehicleTest do
  use TeslaMate.VehicleCase, async: true

  describe "starting" do
    @tag :capture_log
    test "handles unkown and faulty states", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "unknown"}},
        {:error, %TeslaApi.Error{message: "boom"}}
      ]

      :ok = start_vehicle(name, events)

      refute_receive _
    end

    test "handles online state", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car_id, :online}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "handles offline state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car_id, :offline}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :offline}}}

      refute_receive _
    end

    test "handles asleep state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car_id, :asleep}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      refute_receive _
    end
  end

  describe "resume_logging/1" do
    alias TeslaMate.Vehicles.Vehicle

    test "leaves suspended and restores previous state", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, charging_event(0, "Complete", 5.0)},
        {:ok, charging_event(0, "Complete", 5.0)},
        {:ok, charging_event(0, "Unplugged", 5.0)}
      ]

      :ok =
        start_vehicle(name, events,
          sudpend_after_idle_min: round(1 / 60),
          suspend_min: 10_000
        )

      # Online
      assert_receive {:start_state, car_id, :online}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      # Charging (compliete)
      assert_receive {:start_charging_process, ^car_id, _}
      assert_receive {:insert_charge, _, %{charge_energy_added: 5.0}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging_complete}}}

      # suspended
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

      # Resuming
      assert :ok = Vehicle.resume_logging(name)

      # Charging continues
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging_complete}}}

      # Unplugging
      assert_receive {:close_charging_process, _}

      # Online
      assert_receive {:start_state, ^car_id, :online}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      # Suspended, again
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

      refute_receive _
    end

    test "increases polling frequency if asleep", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car_id, :asleep}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      assert :ok = Vehicle.resume_logging(name)

      assert_receive {:start_state, ^car_id, :online}, 100
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end
  end
end
