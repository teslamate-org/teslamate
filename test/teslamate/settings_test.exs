defmodule TeslaMate.SettingsTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Settings.Settings, as: S
  alias TeslaMate.Settings

  describe "settings" do
    @update_attrs %{unit_of_length: :mi, unit_of_temperature: :F}
    @invalid_attrs %{unit_of_length: nil, unit_of_temperature: nil}

    test "get_settings!/0 returns the settings" do
      assert settings = Settings.get_settings!()
      assert settings.unit_of_length == :km
      assert settings.unit_of_temperature == :C
    end

    test "update_settings/2 with valid data updates the settings" do
      settings = Settings.get_settings!()
      assert {:ok, %S{} = settings} = Settings.update_settings(settings, @update_attrs)
      assert settings.unit_of_length == :mi
      assert settings.unit_of_temperature == :F
    end

    test "update_settings/2 with invalid data returns error changeset" do
      settings = Settings.get_settings!()
      assert {:error, %Ecto.Changeset{}} = Settings.update_settings(settings, @invalid_attrs)
      assert ^settings = Settings.get_settings!()
    end
  end
end
