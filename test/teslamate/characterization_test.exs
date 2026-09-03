defmodule TeslaMate.CharacterizationTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Characterization

  test "no orphaned goldens" do
    assert Characterization.orphans() == []
  end

  test "a declared only: target exists" do
    assert Characterization.only_target_error() == nil
  end

  @tag :tmp_dir
  test "recording refuses an await already satisfied at the barrier", %{tmp_dir: tmp} do
    t0 = 1_704_067_200_000

    scenario = %{
      "description" => "vacuity machinery probe",
      "car" => %{
        "eid" => 42,
        "vid" => 1000,
        "vin" => "5YJ3E1EA1KF000001",
        "model" => "3",
        "name" => "blue",
        "efficiency" => 0.153
      },
      "settings" => %{
        "use_streaming_api" => false,
        "suspend_after_idle_min" => 100_000,
        "suspend_min" => 100_000
      },
      "await" => %{"state" => "online"},
      "events" => [park_event(t0), park_event(t0 + 10_000)]
    }

    scenario_path = Path.join(tmp, "vacuous.json")
    File.write!(scenario_path, Jason.encode!(scenario))

    pair = %Characterization.Pair{
      name: "vacuous",
      scenario_path: scenario_path,
      golden_path: Path.join(tmp, "vacuous_golden.json"),
      golden_exists?: false,
      selftest?: false
    }

    assert_raise RuntimeError, ~r/already fully satisfied at the barrier/, fn ->
      Characterization.record_pair(pair)
    end
  end

  @tag :tmp_dir
  test "a declared restart that never happens fails the replay", %{tmp_dir: tmp} do
    t0 = 1_704_067_200_000

    scenario = %{
      "description" => "expect_restart machinery probe",
      "car" => %{
        "eid" => 42,
        "vid" => 1000,
        "vin" => "5YJ3E1EA1KF000001",
        "model" => "3",
        "name" => "blue",
        "efficiency" => 0.153
      },
      "settings" => %{
        "use_streaming_api" => false,
        "suspend_after_idle_min" => 100_000,
        "suspend_min" => 100_000
      },
      "await" => %{"state" => "asleep"},
      "expect_restart" => true,
      "events" => [
        park_event(t0),
        park_event(t0 + 10_000),
        %{"vehicle" => %{"state" => "asleep"}}
      ]
    }

    scenario_path = Path.join(tmp, "no_crash.json")
    File.write!(scenario_path, Jason.encode!(scenario))

    pair = %Characterization.Pair{
      name: "no_crash",
      scenario_path: scenario_path,
      golden_path: Path.join(tmp, "no_crash_golden.json"),
      golden_exists?: false,
      selftest?: false
    }

    assert_raise ExUnit.AssertionError, ~r/the vehicle never went down/, fn ->
      Characterization.record_pair(pair)
    end
  end

  @tag :tmp_dir
  test "a scenario ending in a stream event raises", %{tmp_dir: tmp} do
    scenario =
      base_scenario("stream terminal probe", [
        park_event(1_704_067_200_000),
        %{"stream" => "1704067210000,0,621.4,60,10,120,52.5,13.4,0,,180,200,300"}
      ])

    assert_raise RuntimeError, ~r/cannot end in a stream, call or clock event/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "stream_terminal", scenario))
    end
  end

  @tag :tmp_dir
  test "an unsupported stream_control raises with the deadlock rationale", %{tmp_dir: tmp} do
    scenario =
      base_scenario("stream control probe", [
        %{"stream_control" => "too_many_disconnects"},
        park_event(1_704_067_200_000)
      ])

    assert_raise ArgumentError, ~r/would deadlock against the serve boundary/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "stream_control", scenario))
    end
  end

  @tag :tmp_dir
  test "a scenario ending in an error event raises", %{tmp_dir: tmp} do
    scenario =
      base_scenario("error terminal probe", [
        park_event(1_704_067_200_000),
        %{"error" => "vehicle_unavailable"}
      ])

    assert_raise RuntimeError, ~r/cannot end in an error event/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "error_terminal", scenario))
    end
  end

  @tag :tmp_dir
  test "a terminal reached through a two-call cycle raises", %{tmp_dir: tmp} do
    t0 = 1_704_067_200_000

    scenario =
      base_scenario("two-call terminal probe", [
        park_event(t0),
        %{"error" => "vehicle_unavailable"},
        park_event(t0 + 10_000)
      ])
      |> put_in(["settings", "use_streaming_api"], false)

    assert_raise RuntimeError, ~r/reached through a two-call cycle/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "two_call_terminal", scenario))
    end
  end

  @tag :tmp_dir
  test "a rejected call is recorded into the golden, not raised", %{tmp_dir: tmp} do
    t0 = 1_704_067_200_000

    strict =
      update_in(park_event(t0 + 10_000), ["vehicle", "vehicle_state"], fn vs ->
        Map.put(vs, "is_user_present", true)
      end)

    scenario =
      base_scenario("rejected call probe", [
        Map.put(park_event(t0), "snapshot", true),
        %{"call" => "suspend_logging"},
        strict,
        %{"vehicle" => %{"state" => "asleep"}}
      ])
      |> Map.put("await", %{"state" => "asleep"})

    pair = tmp_pair(tmp, "rejected_call", scenario)
    Characterization.record_pair(pair)

    golden = pair.golden_path |> File.read!() |> Jason.decode!()
    assert golden["calls"] == [%{"suspend_logging" => %{"error" => "user_present"}}]
  end

  @tag :tmp_dir
  test "a scenario ending in a call event raises", %{tmp_dir: tmp} do
    scenario =
      base_scenario("call terminal probe", [
        park_event(1_704_067_200_000),
        %{"call" => "suspend_logging"}
      ])

    assert_raise RuntimeError, ~r/cannot end in a stream, call or clock event/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "call_terminal", scenario))
    end
  end

  @tag :tmp_dir
  test "an unsupported call raises", %{tmp_dir: tmp} do
    scenario =
      base_scenario("call whitelist probe", [
        %{"call" => "resume_logging"},
        park_event(1_704_067_200_000)
      ])

    assert_raise ArgumentError, ~r/unsupported call/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "call_whitelist", scenario))
    end
  end

  @tag :tmp_dir
  test "a replay ending in :suspended raises", %{tmp_dir: tmp} do
    t0 = 1_704_067_200_000

    scenario =
      base_scenario("suspended terminal probe", [
        Map.put(park_event(t0), "snapshot", true),
        %{"call" => "suspend_logging"},
        park_event(t0 + 10_000)
      ])

    assert_raise RuntimeError, ~r/ends in :suspended/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "suspended_terminal", scenario))
    end
  end

  @tag :tmp_dir
  test "a clock event stepping backwards raises", %{tmp_dir: tmp} do
    t0 = 1_704_067_200_000

    scenario =
      base_scenario("backward clock probe", [
        park_event(t0),
        %{"clock" => t0 - 1_000},
        park_event(t0 + 10_000)
      ])

    assert_raise RuntimeError, ~r/the clock only moves forward/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "backward_clock", scenario))
    end
  end

  @tag :tmp_dir
  test "the clock ticks on a timestamp-less serve, so a state row never collapses",
       %{tmp_dir: tmp} do
    scenario =
      base_scenario("clock tick probe", [
        park_event(1_704_067_200_000),
        park_event(1_704_067_210_000),
        %{"vehicle" => %{"state" => "asleep"}}
      ])
      |> put_in(["settings", "use_streaming_api"], false)
      |> Map.put("await", %{"state" => "asleep"})

    pair = tmp_pair(tmp, "clock_tick", scenario)
    Characterization.record_pair(pair)

    golden = pair.golden_path |> File.read!() |> Jason.decode!()
    [online, _asleep] = golden["database"]["states"]
    assert online["start_date"] != online["end_date"]
    assert length(golden["mqtt"]["teslamate/cars/$car/since"]) == 2
  end

  @tag :tmp_dir
  test "a scenario ending in a clock event raises", %{tmp_dir: tmp} do
    scenario =
      base_scenario("clock terminal probe", [
        park_event(1_704_067_200_000),
        %{"clock" => 1_704_067_500_000}
      ])

    assert_raise RuntimeError, ~r/cannot end in a stream, call or clock event/, fn ->
      Characterization.record_pair(tmp_pair(tmp, "clock_terminal", scenario))
    end
  end

  defp base_scenario(description, events) do
    %{
      "description" => description,
      "car" => %{
        "eid" => 42,
        "vid" => 1000,
        "vin" => "5YJ3E1EA1KF000001",
        "model" => "3",
        "name" => "blue",
        "efficiency" => 0.153
      },
      "settings" => %{
        "use_streaming_api" => true,
        "suspend_after_idle_min" => 100_000,
        "suspend_min" => 100_000
      },
      "events" => events
    }
  end

  defp tmp_pair(tmp, name, scenario) do
    scenario_path = Path.join(tmp, "#{name}.json")
    File.write!(scenario_path, Jason.encode!(scenario))

    %Characterization.Pair{
      name: name,
      scenario_path: scenario_path,
      golden_path: Path.join(tmp, "#{name}_golden.json"),
      golden_exists?: false,
      selftest?: false
    }
  end

  defp park_event(ts) do
    %{
      "vehicle" => %{
        "id" => 42,
        "vehicle_id" => 1000,
        "vin" => "5YJ3E1EA1KF000001",
        "state" => "online",
        "display_name" => "blue",
        "charge_state" => %{
          "timestamp" => ts,
          "battery_level" => 80,
          "usable_battery_level" => 79,
          "ideal_battery_range" => 250.0,
          "battery_range" => 240.0,
          "est_battery_range" => 230.5,
          "charging_state" => "Disconnected"
        },
        "drive_state" => %{
          "timestamp" => ts,
          "latitude" => 52.514521,
          "longitude" => 13.350144,
          "heading" => 120,
          "power" => 0,
          "shift_state" => nil,
          "speed" => nil
        },
        "climate_state" => %{
          "timestamp" => ts,
          "outside_temp" => 12.5,
          "inside_temp" => 18.0,
          "is_climate_on" => false
        },
        "vehicle_state" => %{
          "timestamp" => ts,
          "car_version" => "2026.20.1 abc123",
          "odometer" => 10_000.0,
          "locked" => true,
          "sentry_mode" => false,
          "is_user_present" => false
        },
        "vehicle_config" => %{
          "timestamp" => ts,
          "car_type" => "model3",
          "trim_badging" => "74d",
          "exterior_color" => "DeepBlue",
          "wheel_type" => "Pinwheel18",
          "spoiler_type" => "None"
        }
      }
    }
  end

  for pair <- Characterization.pairs() do
    prefix = if pair.selftest?, do: "selftest ", else: ""

    test "replays #{prefix}#{pair.name}" do
      Characterization.run(unquote(Macro.escape(pair)))
    end
  end
end
