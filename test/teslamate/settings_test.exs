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
      preferred_range: :rated
    }
    @invalid_attrs %{
      unit_of_length: nil,
      unit_of_temperature: nil,
      suspend_min: nil,
      suspend_after_idle_min: nil,
      req_no_shift_state_reading: nil,
      req_no_temp_reading: nil,
      req_not_unlocked: nil,
      preferred_range: nil
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
  end
end
