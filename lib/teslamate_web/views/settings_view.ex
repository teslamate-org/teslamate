defmodule TeslaMateWeb.SettingsView do
  use TeslaMateWeb, :view

  alias TeslaMate.Settings.GlobalSettings

  @language_tags (GlobalSettings.supported_languages() ++ [{"Norwegian", "nb"}])
                 |> Enum.map(fn {key, val} -> {val, key} end)
                 |> Enum.into(%{})

  @supported_ui_languages TeslaMateWeb.Cldr.known_locale_names()
                          |> Enum.reject(&(&1 in ["en-001", "root"]))
                          |> Enum.sort()
                          |> Enum.map(&{Map.get(@language_tags, &1, &1), &1})

  def supported_ui_languages, do: @supported_ui_languages
end
