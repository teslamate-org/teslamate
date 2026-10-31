defmodule TeslaMate.SettingsTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Settings.{GlobalSettings, CarSettings}
  alias TeslaMate.{Settings, Log}

  import TestHelper, only: [decimal: 1]

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{
        efficiency: 0.153,
        eid: 42,
        model: "S",
        vid: 42,
        name: "foo",
        trim_badging: "P100D",
        vin: "12345F"
      })
      |> Log.create_car()

    car
  end

  describe "global_settings" do
    @update_attrs %{
      unit_of_length: :mi,
      unit_of_temperature: :F,
      preferred_range: :rated,
      base_url: "https://testlamate.exmpale.com",
      grafana_url: "https://grafana.exmpale.com",
      language: "de",
      theme_mode: :dark
    }
    @invalid_attrs %{
      unit_of_length: nil,
      unit_of_temperature: nil,
      preferred_range: nil,
      base_url: nil,
      grafana_url: nil,
      language: "foo",
      theme_mode: nil
    }

    test "get_global_settings!/0 returns the settings" do
      assert settings = Settings.get_global_settings!()
      assert settings.unit_of_length == :km
      assert settings.unit_of_temperature == :C
      assert settings.preferred_range == :rated
      assert settings.base_url == nil
      assert settings.grafana_url == nil
      assert settings.language == "en"
      assert settings.theme_mode == :system
    end

    test "update_global_settings/2 with valid data updates the settings" do
      settings = Settings.get_global_settings!()

      assert {:ok, %GlobalSettings{} = settings} =
               Settings.update_global_settings(settings, @update_attrs)

      refute_received {:pause, _, _}

      assert settings.unit_of_length == :mi
      assert settings.unit_of_temperature == :F
      assert settings.preferred_range == :rated
      assert settings.base_url == "https://testlamate.exmpale.com"
      assert settings.grafana_url == "https://grafana.exmpale.com"
      assert settings.language == "de"
      assert settings.theme_mode == :dark
    end

    test "update_global_settings/2 with invalid data returns error changeset" do
      settings = Settings.get_global_settings!()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Settings.update_global_settings(settings, @invalid_attrs)

      assert errors_on(changeset) == %{
               unit_of_length: ["can't be blank"],
               unit_of_temperature: ["can't be blank"],
               preferred_range: ["can't be blank"],
               language: ["is not supported"],
               theme_mode: ["can't be blank"]
             }

      assert ^settings = Settings.get_global_settings!()
    end

    test "validate the base url" do
      settings = Settings.get_global_settings!()

      assert {:ok, %GlobalSettings{base_url: "http://example.com"}} =
               Settings.update_global_settings(settings, %{base_url: "http://example.com/"})

      assert {:ok, %GlobalSettings{base_url: "http://example.com/foo"}} =
               Settings.update_global_settings(settings, %{base_url: "  http://example.com/foo/ "})

      cases = [
        {"ftp://example", "invalid scheme"},
        {"example.com", "is missing a scheme (e.g. https)"},
        {"https://", "is missing a host"}
      ]

      for {base_url, message} <- cases do
        assert {:error, changeset} =
                 Settings.update_global_settings(settings, %{base_url: base_url})

        assert errors_on(changeset) == %{base_url: [message]}
      end
    end

    test "empty strings become nil" do
      assert {:ok,
              %GlobalSettings{
                base_url: "https://testlamate.exmpale.com",
                grafana_url: "https://grafana.exmpale.com"
              } = settings} =
               Settings.get_global_settings!()
               |> Settings.update_global_settings(@update_attrs)

      refute_received {:pause, _, _}

      assert {:ok, %GlobalSettings{grafana_url: nil, base_url: nil}} =
               Settings.update_global_settings(settings, %{grafana_url: "     ", base_url: ""})
    end
  end

  describe "car settings" do
    @update_attrs %{
      suspend_min: 60,
      suspend_after_idle_min: 60,
      req_not_unlocked: true,
      free_supercharging: true,
      use_streaming_api: false,
      enabled: true,
      lfp_battery: false
    }
    @invalid_attrs %{
      suspend_min: nil,
      suspend_after_idle_min: nil,
      req_not_unlocked: nil,
      free_supercharging: nil,
      use_streaming_api: nil,
      enabled: nil,
      lfp_battery: nil
    }

    test "get_car_settings/0 returns the settings" do
      car = car_fixture()

      assert [settings] = Settings.get_car_settings()
      assert settings.id == car.settings_id
      assert settings.suspend_min == 21
      assert settings.suspend_after_idle_min == 15
      assert settings.req_not_unlocked == false
      assert settings.free_supercharging == false
      assert settings.use_streaming_api == true
      assert settings.enabled == true
      assert settings.lfp_battery == false
    end

    test "get_car_settings/0 orders results by {display_priority, id}" do
      first = car_fixture(%{eid: 1, vid: 1, vin: "1", display_priority: 2})
      second = car_fixture(%{eid: 2, vid: 2, vin: "2", display_priority: 1})
      third = car_fixture(%{eid: 3, vid: 3, vin: "3", display_priority: 1})

      assert Settings.get_car_settings() |> Enum.map(& &1.car.id) ==
               [second.id, third.id, first.id]
    end

    test "update_car_settings/2 with valid data updates the settings" do
      car = car_fixture()
      [settings] = Settings.get_car_settings()

      assert {:ok, %CarSettings{} = settings} =
               Settings.update_car_settings(settings, @update_attrs)

      assert settings.id == car.settings_id
      assert settings.suspend_min == 60
      assert settings.suspend_after_idle_min == 60
      assert settings.req_not_unlocked == true
      assert settings.free_supercharging == true
      assert settings.use_streaming_api == false
      assert settings.enabled == true
      assert settings.lfp_battery == false
    end

    test "update_car_settings/2 publishes the settings" do
      car = car_fixture()
      :ok = Settings.subscribe_to_changes(car)

      assert [settings] = Settings.get_car_settings()

      assert {:ok, %CarSettings{} = settings} =
               Settings.update_car_settings(settings, @update_attrs)

      assert_receive ^settings
    end

    test "update_car_settings/2 with invalid data returns error changeset" do
      _car = car_fixture()
      [settings] = Settings.get_car_settings()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Settings.update_car_settings(settings, @invalid_attrs)

      assert errors_on(changeset) == %{
               req_not_unlocked: ["can't be blank"],
               suspend_after_idle_min: ["can't be blank"],
               suspend_min: ["can't be blank"],
               free_supercharging: ["can't be blank"],
               use_streaming_api: ["can't be blank"],
               enabled: ["can't be blank"],
               lfp_battery: ["can't be blank"]
             }

      assert [^settings] = Settings.get_car_settings()
    end
  end

  describe "language" do
    alias TeslaMate.Locations.Address
    alias TeslaMate.{Locations, Mutex}

    import ExUnit.CaptureLog

    defp address_fixture(attrs) do
      {:ok, %Address{} = address} =
        attrs
        |> Enum.into(%{
          display_name: "foo",
          name: "0",
          latitude: 0,
          longitude: 0,
          state: "Berlin",
          country: "Germany",
          osm_id: 0,
          osm_type: "way",
          raw: %{}
        })
        |> Locations.create_address()

      address
    end

    # Holds the language changes back until `release/1`
    defp hold_language_changes do
      test = self()

      holder =
        Task.async(fn ->
          Mutex.run(Settings.language_change_mutex(), fn ->
            send(test, :holding)
            receive do: (:release -> :ok)
          end)
        end)

      assert_receive :holding
      holder
    end

    defp release(holder) do
      send(holder.pid, :release)
      assert :ok = Task.await(holder)
    end

    # Starts a language change and returns once it waits for its turn
    defp queue_language_change(settings, lang) do
      mutex = Process.whereis(Settings.language_change_mutex())
      :erlang.trace(mutex, true, [:receive])

      %Task{pid: pid} =
        task = Task.async(fn -> Settings.update_global_settings(settings, %{language: lang}) end)

      assert_receive {:trace, ^mutex, :receive, {:"$gen_call", {^pid, _}, :acquire}}
      :erlang.trace(mutex, false, [:receive])
      task
    end

    test "refreshes all addresses when changing the language" do
      settings = Settings.get_global_settings!()

      address_fixture(%{display_name: "foo", name: "0", osm_id: 0})
      address_fixture(%{display_name: "bar", name: "1", osm_id: 1})

      assert {:ok, _} =
               Settings.update_global_settings(settings, %{language: "nl"})

      refute_received {:pause, _, _}

      assert [
               %Address{
                 name: "0",
                 state: "Berlin_nl",
                 country: "nl",
                 latitude: decimal("0.000000"),
                 longitude: decimal("0.000000")
               },
               %Address{
                 name: "1",
                 state: "Berlin_nl",
                 country: "nl",
                 latitude: decimal("0.000000"),
                 longitude: decimal("0.000000")
               }
             ] = Repo.all(from a in Address, order_by: 1)
    end

    test "reverse geocodes the addresses that the lookup does not return" do
      settings = Settings.get_global_settings!()

      address_fixture(%{
        display_name: "not_in_lookup",
        name: "0",
        latitude: 52.0,
        longitude: 8.5,
        osm_id: 103_619_766,
        osm_type: "way"
      })

      assert {:ok, %GlobalSettings{language: "nl"}} =
               Settings.update_global_settings(settings, %{language: "nl"})

      # the lookup came first, so Nominatim gets a break before the reverse geocoding
      assert_received {:pause, 1500, checked_out?: false}
      refute_received {:pause, _, _}

      assert [
               %Address{
                 display_name:
                   "Von-der-Recke-Straße, Mitte, Bielefeld, Regierungsbezirk Detmold, Nordrhein-Westfalen, 33602, Deutschland",
                 name: "0",
                 city: "Bielefeld",
                 country: "Deutschland",
                 neighbourhood: "Mitte",
                 state: "Nordrhein-Westfalen",
                 osm_id: 103_619_766
               }
             ] = Repo.all(Address)
    end

    test "skips addresses that Nominatim now reports as a different place" do
      settings = Settings.get_global_settings!()

      %Address{id: id} =
        address =
        address_fixture(%{display_name: "not_in_lookup", osm_id: 1, osm_type: "way"})

      log =
        capture_log(fn ->
          assert {:ok, %GlobalSettings{language: "nl"}} =
                   Settings.update_global_settings(settings, %{language: "nl"})
        end)

      assert log =~ "Address does not match! Skipping"
      assert log =~ "osm_id: 1 -> 103619766"

      assert_received {:pause, 1500, checked_out?: false}
      refute_received {:pause, _, _}

      zero = Decimal.new("0.000000")
      assert [%Address{id: ^id} = skipped] = Repo.all(Address)
      assert skipped == %Address{address | latitude: zero, longitude: zero}
    end

    test "returns the error of the reverse geocoding and changes nothing" do
      settings = Settings.get_global_settings!()

      a0 = address_fixture(%{display_name: "foo", name: "0", osm_id: 0})

      a1 =
        address_fixture(%{
          display_name: "not_in_lookup",
          name: "1",
          latitude: 99.9,
          longitude: 99.9,
          osm_id: 1
        })

      assert {:error, :induced_error} =
               Settings.update_global_settings(settings, %{language: "nl"})

      assert_received {:pause, 1500, checked_out?: false}
      refute_received {:pause, _, _}

      assert %GlobalSettings{language: "en"} = Settings.get_global_settings!()

      zero = Decimal.new("0.000000")
      assert [r0, r1] = Repo.all(from a in Address, order_by: 1)
      assert r0 == %Address{a0 | latitude: zero, longitude: zero}

      assert r1 == %Address{
               a1
               | latitude: Decimal.new("99.900000"),
                 longitude: Decimal.new("99.900000")
             }
    end

    test "fetches the addresses in chunks, pausing between the requests outside of a transaction" do
      settings = Settings.get_global_settings!()

      for i <- 1..50, do: address_fixture(%{name: "#{i}", osm_id: i})

      address_fixture(%{
        display_name: "not_in_lookup",
        latitude: 52.0,
        longitude: 8.5,
        osm_id: 103_619_766
      })

      assert {:ok, %GlobalSettings{language: "nl"}} =
               Settings.update_global_settings(settings, %{language: "nl"})

      # two lookups (50 addresses and 1) and one reverse geocoding: two pauses
      assert_received {:pause, 1500, checked_out?: false}
      assert_received {:pause, 1500, checked_out?: false}
      refute_received {:pause, _, _}

      assert 50 == Repo.aggregate(from(a in Address, where: a.country == "nl"), :count)
      assert 1 == Repo.aggregate(from(a in Address, where: a.country == "Deutschland"), :count)
    end

    @tag :capture_log
    test "returns error tuple" do
      settings = Settings.get_global_settings!()

      a0 = address_fixture(%{display_name: "foo", name: "0", osm_id: 0})
      a1 = address_fixture(%{display_name: "error", name: "1", osm_id: 1})

      assert {:error, :boom} =
               Settings.update_global_settings(settings, %{language: "nl"})

      refute_received {:pause, _, _}

      assert %GlobalSettings{language: "en"} = Settings.get_global_settings!()

      zero = Decimal.new("0.000000")
      assert [r0, r1] = Repo.all(from a in Address, order_by: 1)
      assert r0 == %Address{a0 | latitude: zero, longitude: zero}
      assert r1 == %Address{a1 | latitude: zero, longitude: zero}
    end

    test "waits for a language change that is still running" do
      settings = Settings.get_global_settings!()
      address_fixture(%{display_name: "foo", name: "0", osm_id: 0})

      holder = hold_language_changes()
      waiting = queue_language_change(settings, "nl")

      # Changes of other settings do not wait
      assert {:ok, %GlobalSettings{unit_of_length: :mi, language: "en"}} =
               Settings.update_global_settings(settings, %{unit_of_length: :mi})

      release(holder)

      # the language change wrote only the language, and returns what is saved
      assert {:ok, %GlobalSettings{language: "nl", unit_of_length: :mi} = changed} =
               Task.await(waiting)

      assert changed == Settings.get_global_settings!()
      assert [%Address{country: "nl"}] = Repo.all(Address)
    end

    test "reads the addresses only once it is its turn" do
      settings = Settings.get_global_settings!()

      # the country already is the one the lookup returns for "nl"
      %Address{id: id} = address_fixture(%{country: "nl"})

      holder = hold_language_changes()
      waiting = queue_language_change(settings, "nl")

      # as if the language change before had committed
      assert {1, _} =
               Repo.update_all(from(a in Address, where: a.id == ^id), set: [country: "Germany"])

      release(holder)

      assert {:ok, %GlobalSettings{language: "nl"}} = Task.await(waiting)
      assert %Address{country: "nl", state: "Berlin_nl"} = Repo.get!(Address, id)
    end
  end

  describe "efficiencies" do
    alias TeslaMate.Log.{Car, ChargingProcess, Position}
    alias TeslaMate.Log

    test "triggers a recalculaten of efficiencies if the preferred range changes" do
      %Car{efficiency: nil} = car = car_fixture(%{efficiency: nil})

      data = [
        {293.9, 293.9, nil, nil, 0.0, 59, 59, 0},
        {293.2, 303.4, nil, nil, 1.65, 59, 61, 33},
        {302.5, 302.5, nil, nil, 0.0, 61, 61, 0},
        {302.5, 302.5, nil, nil, 0.0, 61, 61, 0},
        {302.1, 309.5, nil, nil, 1.14, 61, 62, 23},
        {71.9, 350.5, nil, nil, 42.21, 14, 70, 27},
        {181.0, 484.0, nil, nil, 46.13, 36, 97, 46},
        {312.3, 324.9, nil, nil, 1.75, 63, 65, 6},
        {325.6, 482.7, nil, nil, 23.71, 65, 97, 34},
        {80.5, 412.4, nil, nil, 50.63, 16, 83, 70},
        {259.7, 426.2, nil, nil, 25.56, 52, 85, 36},
        {105.5, 361.4, nil, nil, 38.96, 21, 72, 22},
        {143.1, 282.5, nil, nil, 21.11, 29, 57, 15},
        {111.6, 406.9, nil, nil, 44.93, 22, 82, 36},
        {115.0, 453.2, nil, nil, 51.49, 23, 91, 38},
        {112.5, 112.5, 111.5, 112.5, 0.0, 23, 23, 1},
        {109.7, 139.7, 108.7, 139.7, 4.57, 22, 28, 26},
        {63.9, 142.3, 64.9, 142.3, 11.82, 13, 29, 221},
        {107.9, 450.1, 108.9, 450.1, 52.1, 22, 90, 40}
      ]

      :ok = insert_charging_processes(car, data)
      settings = Settings.get_global_settings!()

      # no change
      assert {:ok, settings} =
               Settings.update_global_settings(settings, %{preferred_range: :rated})

      assert %Car{efficiency: nil} = Log.get_car!(car.id)

      # changed
      assert {:ok, settings} =
               Settings.update_global_settings(settings, %{preferred_range: :ideal})

      assert %Car{efficiency: 0.152} = Log.get_car!(car.id)

      # changed back
      assert {:ok, _settings} =
               Settings.update_global_settings(settings, %{preferred_range: :rated})

      assert %Car{efficiency: 0.15} = Log.get_car!(car.id)
    end

    @valid_pos_attrs %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0}

    defp insert_charging_processes(car, data) do
      {:ok, %Position{id: position_id}} = Log.insert_position(car, @valid_pos_attrs)

      data =
        for {sir, eir, srr, err, ca, sl, el, d} <- data do
          %{
            car_id: car.id,
            start_date: DateTime.utc_now(),
            position_id: position_id,
            start_ideal_range_km: sir,
            end_ideal_range_km: eir,
            start_rated_range_km: srr,
            end_rated_range_km: err,
            charge_energy_added: ca,
            start_battery_level: sl,
            end_battery_level: el,
            duration_min: d
          }
        end

      {_, nil} = Repo.insert_all(ChargingProcess, data)

      :ok
    end
  end
end
