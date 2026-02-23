defmodule Mix.Tasks.Seed.SampleData do
  use Mix.Task

  @shortdoc "Seeds the database with sample data for API development"

  @moduledoc """
  Seeds the database with realistic sample data for development and testing.

      mix seed.sample_data

  Creates:
  - 1 car with settings
  - 10 drives with positions
  - 5 charging sessions with charge data points
  - Addresses and a geofence
  """

  alias TeslaMate.Repo
  alias TeslaMate.Log.{Car, Drive, Position, ChargingProcess, Charge, State}
  alias TeslaMate.Locations.{Address, GeoFence}
  alias TeslaMate.Settings.CarSettings

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Seeding sample data...")

    # Create car settings
    {:ok, settings} =
      %CarSettings{}
      |> CarSettings.changeset(%{
        suspend_min: 21,
        suspend_after_idle_min: 15,
        req_not_unlocked: false,
        free_supercharging: false,
        use_streaming_api: true,
        enabled: true,
        lfp_battery: false
      })
      |> Repo.insert()

    # Create car
    {:ok, car} =
      %Car{settings_id: settings.id}
      |> Car.changeset(%{
        eid: 123_456_789,
        vid: 987_654_321,
        vin: "5YJ3E1EA1NF000001",
        name: "My Tesla",
        model: "3",
        trim_badging: "P",
        marketing_name: "Model 3 Performance",
        exterior_color: "MidnightSilver",
        wheel_type: "Stiletto20",
        spoiler_type: "Passive",
        efficiency: 0.152
      })
      |> Repo.insert()

    IO.puts("  Created car: #{car.name} (id: #{car.id})")

    # Create a geofence
    {:ok, home_geofence} =
      %GeoFence{}
      |> GeoFence.changeset(%{
        name: "Home",
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 50,
        billing_type: :per_kwh,
        cost_per_unit: 0.12,
        session_fee: 0
      })
      |> Repo.insert()

    # Create addresses
    {:ok, home_addr} = create_address("123 Main St, San Francisco, CA", 37.7749, -122.4194)
    {:ok, work_addr} = create_address("456 Market St, San Francisco, CA", 37.7899, -122.4009)
    {:ok, mall_addr} = create_address("Westfield SF Centre, San Francisco, CA", 37.7841, -122.4065)
    {:ok, park_addr} = create_address("Golden Gate Park, San Francisco, CA", 37.7694, -122.4862)
    {:ok, sc_addr} = create_address("Tesla Supercharger, Daly City, CA", 37.6879, -122.4702)

    # Create a current state
    {:ok, _state} =
      %State{car_id: car.id}
      |> State.changeset(%{state: :online, start_date: DateTime.utc_now()})
      |> Repo.insert()

    # Create drives
    base_time = DateTime.utc_now() |> DateTime.add(-30 * 24 * 3600, :second)

    drive_configs = [
      {home_addr, work_addr, nil, nil, 12.5, 25, 37.7749, -122.4194, 37.7899, -122.4009},
      {work_addr, mall_addr, nil, nil, 3.2, 10, 37.7899, -122.4009, 37.7841, -122.4065},
      {mall_addr, home_addr, nil, home_geofence, 8.7, 20, 37.7841, -122.4065, 37.7749, -122.4194},
      {home_addr, park_addr, home_geofence, nil, 15.3, 30, 37.7749, -122.4194, 37.7694, -122.4862},
      {park_addr, home_addr, nil, home_geofence, 15.1, 28, 37.7694, -122.4862, 37.7749, -122.4194},
      {home_addr, sc_addr, home_geofence, nil, 22.0, 35, 37.7749, -122.4194, 37.6879, -122.4702},
      {sc_addr, home_addr, nil, home_geofence, 21.8, 33, 37.6879, -122.4702, 37.7749, -122.4194},
      {home_addr, work_addr, home_geofence, nil, 12.3, 24, 37.7749, -122.4194, 37.7899, -122.4009},
      {work_addr, home_addr, nil, home_geofence, 12.8, 26, 37.7899, -122.4009, 37.7749, -122.4194},
      {home_addr, park_addr, home_geofence, nil, 14.9, 29, 37.7749, -122.4194, 37.7694, -122.4862}
    ]

    for {i, {start_addr, end_addr, start_gf, end_gf, dist, dur, slat, slon, elat, elon}} <-
          Enum.with_index(drive_configs, 1) do
      drive_start = DateTime.add(base_time, i * 3 * 24 * 3600, :second)
      drive_end = DateTime.add(drive_start, dur * 60, :second)

      # Create start and end positions
      {:ok, start_pos} =
        %Position{car_id: car.id}
        |> Position.changeset(%{
          date: drive_start,
          latitude: slat,
          longitude: slon,
          speed: 0,
          power: 0,
          odometer: 10000.0 + i * dist,
          battery_level: 80 - i,
          ideal_battery_range_km: Decimal.new("350.0"),
          rated_battery_range_km: Decimal.new("340.0")
        })
        |> Repo.insert()

      {:ok, end_pos} =
        %Position{car_id: car.id}
        |> Position.changeset(%{
          date: drive_end,
          latitude: elat,
          longitude: elon,
          speed: 0,
          power: 0,
          odometer: 10000.0 + i * dist + dist,
          battery_level: 80 - i - 5,
          ideal_battery_range_km: Decimal.new("330.0"),
          rated_battery_range_km: Decimal.new("320.0")
        })
        |> Repo.insert()

      {:ok, drive} =
        %Drive{car_id: car.id}
        |> Drive.changeset(%{
          start_date: drive_start,
          end_date: drive_end,
          start_position_id: start_pos.id,
          end_position_id: end_pos.id,
          start_address_id: start_addr.id,
          end_address_id: end_addr.id,
          start_geofence_id: if(start_gf, do: start_gf.id),
          end_geofence_id: if(end_gf, do: end_gf.id),
          distance: dist,
          duration_min: dur,
          speed_max: 65 + :rand.uniform(30),
          power_max: 50 + :rand.uniform(100),
          power_min: -60 - :rand.uniform(40),
          start_km: 10000.0 + i * dist,
          end_km: 10000.0 + i * dist + dist,
          start_ideal_range_km: Decimal.new("350.0"),
          end_ideal_range_km: Decimal.new("330.0"),
          start_rated_range_km: Decimal.new("340.0"),
          end_rated_range_km: Decimal.new("320.0"),
          outside_temp_avg: Decimal.new("18.5"),
          inside_temp_avg: Decimal.new("22.0")
        })
        |> Repo.insert()

      # Add intermediate positions to each drive
      for j <- 1..5 do
        frac = j / 6
        t = DateTime.add(drive_start, trunc(dur * 60 * frac), :second)

        %Position{car_id: car.id, drive_id: drive.id}
        |> Position.changeset(%{
          date: t,
          latitude: slat + (elat - slat) * frac,
          longitude: slon + (elon - slon) * frac,
          speed: 30 + :rand.uniform(40),
          power: -10 + :rand.uniform(60),
          odometer: 10000.0 + i * dist + dist * frac,
          battery_level: (80 - i) - trunc(5 * frac),
          ideal_battery_range_km: Decimal.new("340.0"),
          rated_battery_range_km: Decimal.new("330.0")
        })
        |> Repo.insert()
      end

      IO.puts("  Created drive ##{i}: #{dist} km, #{dur} min")
    end

    # Create charging sessions
    charge_configs = [
      {home_addr, home_geofence, 35, 80, 22.5, 45},
      {sc_addr, nil, 20, 90, 45.0, 35},
      {home_addr, home_geofence, 50, 95, 25.0, 60},
      {mall_addr, nil, 40, 75, 18.0, 50},
      {home_addr, home_geofence, 30, 85, 28.0, 55}
    ]

    for {i, {addr, gf, start_soc, end_soc, energy, dur}} <-
          Enum.with_index(charge_configs, 1) do
      charge_start = DateTime.add(base_time, (i * 5 + 1) * 24 * 3600, :second)
      charge_end = DateTime.add(charge_start, dur * 60, :second)

      {:ok, cp_pos} =
        %Position{car_id: car.id}
        |> Position.changeset(%{
          date: charge_start,
          latitude: addr.latitude,
          longitude: addr.longitude,
          speed: 0,
          power: 0,
          odometer: 10200.0 + i * 20,
          battery_level: start_soc
        })
        |> Repo.insert()

      {:ok, cp} =
        %ChargingProcess{car_id: car.id, position_id: cp_pos.id, address_id: addr.id, geofence_id: if(gf, do: gf.id)}
        |> ChargingProcess.changeset(%{
          start_date: charge_start,
          end_date: charge_end,
          charge_energy_added: Decimal.from_float(energy),
          charge_energy_used: Decimal.from_float(energy * 1.05),
          start_ideal_range_km: Decimal.new("200.0"),
          end_ideal_range_km: Decimal.new("350.0"),
          start_rated_range_km: Decimal.new("190.0"),
          end_rated_range_km: Decimal.new("340.0"),
          start_battery_level: start_soc,
          end_battery_level: end_soc,
          duration_min: dur,
          outside_temp_avg: Decimal.new("15.0"),
          cost: if(gf, do: Decimal.from_float(energy * 0.12), else: nil)
        })
        |> Repo.insert()

      # Add charge data points
      num_points = 10

      for j <- 0..(num_points - 1) do
        frac = j / (num_points - 1)
        t = DateTime.add(charge_start, trunc(dur * 60 * frac), :second)
        soc = start_soc + trunc((end_soc - start_soc) * frac)
        power = if(gf == nil, do: 150 - trunc(100 * frac), else: 11)

        %Charge{charging_process_id: cp.id}
        |> Charge.changeset(%{
          date: t,
          battery_level: soc,
          usable_battery_level: soc - 1,
          charge_energy_added: Decimal.from_float(energy * frac),
          charger_actual_current: if(gf == nil, do: 400 - trunc(250 * frac), else: 48),
          charger_phases: if(gf == nil, do: nil, else: 3),
          charger_pilot_current: if(gf == nil, do: 400, else: 48),
          charger_power: power,
          charger_voltage: if(gf == nil, do: 400, else: 230),
          ideal_battery_range_km: Decimal.from_float(200.0 + 150.0 * frac),
          rated_battery_range_km: Decimal.from_float(190.0 + 150.0 * frac),
          outside_temp: Decimal.new("15.0"),
          fast_charger_present: gf == nil,
          fast_charger_brand: if(gf == nil, do: "Tesla"),
          fast_charger_type: if(gf == nil, do: "Tesla Supercharger"),
          conn_charge_cable: if(gf == nil, do: "IEC", else: "SAE")
        })
        |> Repo.insert()
      end

      IO.puts("  Created charging session ##{i}: #{start_soc}% -> #{end_soc}%, #{energy} kWh")
    end

    IO.puts("\nSample data seeded successfully!")
  end

  defp create_address(display_name, lat, lon) do
    %Address{}
    |> Address.changeset(%{
      display_name: display_name,
      latitude: lat,
      longitude: lon,
      osm_id: :rand.uniform(999_999_999),
      osm_type: "way",
      raw: %{}
    })
    |> Repo.insert()
  end
end
