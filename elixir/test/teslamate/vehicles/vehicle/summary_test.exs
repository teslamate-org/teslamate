defmodule TeslaMate.Vehicles.Vehicle.SummaryTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaApi.Vehicle
  alias TeslaApi.Vehicle.State.VehicleState
  alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate

  defp attrs do
    %{
      state: :online,
      since: DateTime.utc_now(),
      healthy?: true,
      car: nil,
      shown: %{},
      polled?: true,
      driving_status: nil
    }
  end

  defp vehicle_with_update(status, version \\ "2024.3.1 abc123") do
    %Vehicle{
      vehicle_state: %VehicleState{
        software_update: %SoftwareUpdate{status: status, version: version}
      }
    }
  end

  test "home distance is rounded and absent home remains nil" do
    shown = %{home_geofence: "foo", home_distance_km: 36.84}
    summary = Summary.into(%Vehicle{}, Map.put(attrs(), :shown, shown))
    assert summary.home_distance_km == 36.8
    assert summary.home_geofence == "foo"
    summary = Summary.into(%Vehicle{}, attrs())
    assert summary.home_distance_km == nil
    assert summary.home_geofence == nil
    refute :home_distance_km in summary.observed_nil

    shown = %{home_geofence: nil, home_distance_km: nil}
    summary = Summary.into(%Vehicle{}, Map.put(attrs(), :shown, shown))
    assert :home_distance_km in summary.observed_nil
    assert :home_geofence in summary.observed_nil
  end

  describe "update_available" do
    test "true when status is 'available'" do
      summary = Summary.into(vehicle_with_update("available"), attrs())
      assert summary.update_available == true
    end

    test "true when status is 'downloading'" do
      summary = Summary.into(vehicle_with_update("downloading"), attrs())
      assert summary.update_available == true
    end

    test "true when status is 'downloading_wifi_wait'" do
      summary = Summary.into(vehicle_with_update("downloading_wifi_wait"), attrs())
      assert summary.update_available == true
    end

    test "true when status is 'scheduled' (download complete, waiting to install)" do
      summary = Summary.into(vehicle_with_update("scheduled"), attrs())
      assert summary.update_available == true
    end

    test "true when status is 'installing'" do
      summary = Summary.into(vehicle_with_update("installing"), attrs())
      assert summary.update_available == true
    end

    test "false when status is empty string (no update)" do
      summary = Summary.into(vehicle_with_update(""), attrs())
      assert summary.update_available == false
    end

    test "nil when software_update is nil" do
      vehicle = %Vehicle{vehicle_state: %VehicleState{software_update: nil}}
      summary = Summary.into(vehicle, attrs())
      assert summary.update_available == nil
    end
  end

  describe "download_perc / install_perc" do
    test "maps download_perc and install_perc from software_update" do
      vehicle = %Vehicle{
        vehicle_state: %VehicleState{
          software_update: %SoftwareUpdate{status: "downloading", download_perc: 100}
        }
      }

      summary = Summary.into(vehicle, attrs())
      assert summary.download_perc == 100
      assert summary.install_perc == nil
    end

    test "maps install_perc while installing" do
      vehicle = %Vehicle{
        vehicle_state: %VehicleState{
          software_update: %SoftwareUpdate{
            status: "installing",
            download_perc: 100,
            install_perc: 42
          }
        }
      }

      summary = Summary.into(vehicle, attrs())
      assert summary.download_perc == 100
      assert summary.install_perc == 42
    end

    test "nil when software_update is nil" do
      vehicle = %Vehicle{vehicle_state: %VehicleState{software_update: nil}}
      summary = Summary.into(vehicle, attrs())
      assert summary.download_perc == nil
      assert summary.install_perc == nil
    end
  end

  describe "update_version" do
    test "strips the build hash from the version string" do
      summary = Summary.into(vehicle_with_update("available", "2024.3.1 abc123"), attrs())
      assert summary.update_version == "2024.3.1"
    end

    test "nil when no version" do
      summary = Summary.into(vehicle_with_update("available", nil), attrs())
      assert summary.update_version == nil
    end
  end
end
