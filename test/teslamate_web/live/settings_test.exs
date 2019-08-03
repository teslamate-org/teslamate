defmodule TeslaMateWeb.SettingsLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Settings

  test "redirects if not signed in", %{conn: conn} do
    assert {:error, %{redirect: %{to: "/sign_in"}}} = live(conn, "/settings")
  end

  @tag :signed_in
  test "shows an unchecked checkbox by default", %{conn: conn} do
    assert {:ok, _view, html} = live(conn, "/settings")

    assert html =~ """
           <input id="settings_use_imperial_units" name="settings[use_imperial_units]" type="checkbox" value="true"> Use imperial units
           """
  end

  @tag :signed_in
  test "reacts to change events", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/settings")

    assert render_change(view, :change, %{settings: %{use_imperial_units: true}}) =~ """
           <input id="settings_use_imperial_units" name="settings[use_imperial_units]" type="checkbox" value="true" checked> Use imperial units
           """

    assert settings = Settings.get_settings!()
    assert settings.use_imperial_units == true

    assert render_change(view, :change, %{settings: %{use_imperial_units: false}}) =~ """
           <input id="settings_use_imperial_units" name="settings[use_imperial_units]" type="checkbox" value="true"> Use imperial units
           """

    assert settings = Settings.get_settings!()
    assert settings.use_imperial_units == false
  end
end
