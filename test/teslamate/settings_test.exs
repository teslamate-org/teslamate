defmodule TeslaMate.SettingsTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Settings.Settings, as: S
  alias TeslaMate.Settings

  describe "settings" do
    @update_attrs %{
      unit_of_length: :mi,
      unit_of_temperature: :F,
      suspend_min: 60,
      suspend_after_idle_min: 60,
      req_no_shift_state_reading: false,
      req_no_temp_reading: false,
      req_not_unlocked: true,
      preferred_range: :rated,
      base_url: "https://testlamate.exmpale.com",
      grafana_url: "https://grafana.exmpale.com"
    }
    @invalid_attrs %{
      unit_of_length: nil,
      unit_of_temperature: nil,
      suspend_min: nil,
      suspend_after_idle_min: nil,
      req_no_shift_state_reading: nil,
      req_no_temp_reading: nil,
      req_not_unlocked: nil,
      preferred_range: nil,
      base_url: nil,
      grafana_url: nil
    }

    test "get_settings!/0 returns the settings" do
      assert settings = Settings.get_settings!()
      assert settings.unit_of_length == :km
      assert settings.suspend_min == 21
      assert settings.suspend_after_idle_min == 15
      assert settings.req_no_shift_state_reading == false
      assert settings.req_no_temp_reading == false
      assert settings.req_not_unlocked == true
      assert settings.preferred_range == :ideal
      assert settings.base_url == nil
      assert settings.grafana_url == nil
    end

    test "update_settings/2 with valid data updates the settings" do
      {:ok, _pid} = start_supervised({Phoenix.PubSub.PG2, name: TeslaMate.PubSub})

      settings = Settings.get_settings!()
      assert {:ok, %S{} = settings} = Settings.update_settings(settings, @update_attrs)
      assert settings.unit_of_length == :mi
      assert settings.unit_of_temperature == :F
      assert settings.suspend_min == 60
      assert settings.suspend_after_idle_min == 60
      assert settings.req_no_shift_state_reading == false
      assert settings.req_no_temp_reading == false
      assert settings.req_not_unlocked == true
      assert settings.preferred_range == :rated
      assert settings.base_url == "https://testlamate.exmpale.com"
      assert settings.grafana_url == "https://grafana.exmpale.com"
    end

    test "update_settings/2 publishes the settings" do
      {:ok, _pid} = start_supervised({Phoenix.PubSub.PG2, name: TeslaMate.PubSub})

      :ok = Settings.subscribe_to_changes()

      assert {:ok, %S{} = settings} =
               Settings.get_settings!()
               |> Settings.update_settings(@update_attrs)

      assert_receive ^settings
    end

    test "update_settings/2 with invalid data returns error changeset" do
      settings = Settings.get_settings!()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Settings.update_settings(settings, @invalid_attrs)

      assert errors_on(changeset) == %{
               req_no_shift_state_reading: ["can't be blank"],
               req_no_temp_reading: ["can't be blank"],
               req_not_unlocked: ["can't be blank"],
               suspend_after_idle_min: ["can't be blank"],
               suspend_min: ["can't be blank"],
               unit_of_length: ["can't be blank"],
               unit_of_temperature: ["can't be blank"],
               preferred_range: ["can't be blank"]
             }

      assert ^settings = Settings.get_settings!()
    end

    test "validate the base url" do
      {:ok, _pid} = start_supervised({Phoenix.PubSub.PG2, name: TeslaMate.PubSub})
      settings = Settings.get_settings!()

      assert {:ok, %S{base_url: "http://example.com"}} =
               Settings.update_settings(settings, %{base_url: "http://example.com/"})

      assert {:ok, %S{base_url: "http://example.com/foo"}} =
               Settings.update_settings(settings, %{base_url: "  http://example.com/foo/  "})

      cases = [
        {"ftp://example", "invalid scheme"},
        {"example.com", "is missing a scheme (e.g. https)"},
        {"https://", "is missing a host"}
      ]

      for {base_url, message} <- cases do
        assert {:error, changeset} = Settings.update_settings(settings, %{base_url: base_url})
        assert errors_on(changeset) == %{base_url: [message]}
      end
    end

    test "empty strings become nil" do
      {:ok, _pid} = start_supervised({Phoenix.PubSub.PG2, name: TeslaMate.PubSub})

      assert {:ok,
              %S{
                base_url: "https://testlamate.exmpale.com",
                grafana_url: "https://grafana.exmpale.com"
              } = settings} =
               Settings.get_settings!()
               |> Settings.update_settings(@update_attrs)

      assert {:ok, %S{grafana_url: nil, base_url: nil}} =
               Settings.update_settings(settings, %{grafana_url: "     ", base_url: ""})
    end
  end

  describe "efficiencies" do
    alias TeslaMate.Log.{Car, ChargingProcess, Position}
    alias TeslaMate.Log

    test "triggers a recalculaten of efficiencies if the preferred range chages" do
      {:ok, _pid} = start_supervised({Phoenix.PubSub.PG2, name: TeslaMate.PubSub})
      %Car{efficiency: nil} = car = car_fixture()

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
      settings = Settings.get_settings!()

      # no change
      assert {:ok, settings} = Settings.update_settings(settings, %{preferred_range: :ideal})
      assert %Car{efficiency: nil} = Log.get_car!(car.id)

      # changed
      assert {:ok, settings} = Settings.update_settings(settings, %{preferred_range: :rated})
      assert %Car{efficiency: 0.15} = Log.get_car!(car.id)

      # changed back
      assert {:ok, settings} = Settings.update_settings(settings, %{preferred_range: :ideal})
      assert %Car{efficiency: 0.152} = Log.get_car!(car.id)
    end

    defp car_fixture(attrs \\ %{}) do
      {:ok, car} =
        attrs
        |> Enum.into(%{eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
        |> Log.create_car()

      car
    end

    @valid_pos_attrs %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0}

    defp insert_charging_processes(car, data) do
      {:ok, %Position{id: position_id}} = Log.insert_position(car, @valid_pos_attrs)

      data =
        for {sir, eir, srr, err, ca, sl, el, d} <- data do
          %{
            car_id: car.id,
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
