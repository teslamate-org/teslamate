defmodule TeslaMate.SettingsTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Settings.Settings, as: S
  alias TeslaMate.Settings

  describe "settings" do
    @update_attrs %{use_imperial_units: true}
    @invalid_attrs %{use_imperial_units: nil}

    test "get_settings!/0 returns the settings" do
      assert settings = Settings.get_settings!()
      assert settings.use_imperial_units == false
    end

    test "update_settings/2 with valid data updates the settings" do
      settings = Settings.get_settings!()
      assert {:ok, %S{} = settings} = Settings.update_settings(settings, @update_attrs)
      assert settings.use_imperial_units == true
    end

    test "update_settings/2 with invalid data returns error changeset" do
      settings = Settings.get_settings!()
      assert {:error, %Ecto.Changeset{}} = Settings.update_settings(settings, @invalid_attrs)
      assert ^settings = Settings.get_settings!()
    end
  end
end
