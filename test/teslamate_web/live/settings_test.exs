defmodule TeslaMateWeb.SettingsLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Settings

  test "redirects if not signed in", %{conn: conn} do
    assert {:error, %{redirect: %{to: "/sign_in"}}} = live(conn, "/settings")
  end

  @tag :signed_in
  test "shows km and C by default", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/settings")

    assert html =~
             ~r(<select id="settings_unit_of_length" .+"><option value="km" selected>km</option><option value="mi">mi</option></select>)

    assert html =~
             ~r(<select id="settings_unit_of_temperature" .+"><option value="C" selected>°C</option><option value="F">°F</option></select>)
  end

  @tag :signed_in
  test "reacts to change events", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/settings")

    assert render_change(view, :change, %{settings: %{unit_of_length: :mi}}) =~
             ~r(<select id="settings_unit_of_length" .+"><option value="km">km</option><option value="mi" selected>mi</option></select>)

    assert settings = Settings.get_settings!()
    assert settings.unit_of_length == :mi

    assert render_change(view, :change, %{settings: %{unit_of_temperature: :F}}) =~
             ~r(<select id="settings_unit_of_temperature" .+"><option value="C">°C</option><option value="F" selected>°F</option></select>)

    assert settings = Settings.get_settings!()
    assert settings.unit_of_temperature == :F
  end
end
