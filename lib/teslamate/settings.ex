defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias TeslaMate.Settings.Settings

  def get_settings! do
    case Repo.all(Settings) do
      [settings] -> settings
      _ -> raise "settings table is corrupted"
    end
  end

  def update_settings(%Settings{} = settings, attrs) do
    settings
    |> Settings.changeset(attrs)
    |> Repo.update()
  end

  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end
end
