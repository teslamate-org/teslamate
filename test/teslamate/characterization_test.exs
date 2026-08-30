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
