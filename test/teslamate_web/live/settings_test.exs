defmodule TeslaMateWeb.SettingsLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Settings

  test "shows km and C by default", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/settings")

    assert html =~
             ~r(<select id="settings_unit_of_length" .+><option value="km" selected>km</option><option value="mi">mi</option></select>)

    assert html =~
             ~r(<select id="settings_unit_of_temperature" .+><option value="C" selected>°C</option><option value="F">°F</option></select>)
  end

  test "shows 12 and 15 minutes by default", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/settings")

    assert html =~
             ~r(<select id="settings_suspend_min" .+>.*<option value="12" selected>12 min</option>.*</select>)

    assert html =~
             ~r(<select id="settings_suspend_after_idle_min" .+>.*<option value="15" selected>15 min</option>.*</select>)
  end

  test "reacts to change events", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/settings")

    assert render_change(view, :change, %{settings: %{unit_of_length: :mi}}) =~
             ~r(<select id="settings_unit_of_length" .+><option value="km">km</option><option value="mi" selected>mi</option></select>)

    assert settings = Settings.get_settings!()
    assert settings.unit_of_length == :mi

    assert render_change(view, :change, %{settings: %{unit_of_temperature: :F}}) =~
             ~r(<select id="settings_unit_of_temperature" .+><option value="C">°C</option><option value="F" selected>°F</option></select>)

    assert settings = Settings.get_settings!()
    assert settings.unit_of_temperature == :F

    assert render_change(view, :change, %{settings: %{suspend_min: 21}}) =~
             ~r(<select id="settings_suspend_min" .+>.*<option value="21" selected>21 min</option>.*</select>)

    assert settings = Settings.get_settings!()
    assert settings.suspend_min == 21

    assert render_change(view, :change, %{settings: %{suspend_after_idle_min: 30}}) =~
             ~r(<select id="settings_suspend_after_idle_min" .+>.*<option value="30" selected>30 min</option>.*</select>)

    assert settings = Settings.get_settings!()
    assert settings.suspend_after_idle_min == 30
  end
end
