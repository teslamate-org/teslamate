defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias TeslaMate.Settings.Settings

  @topic inspect(__MODULE__)

  def get_settings! do
    case Repo.all(Settings) do
      [settings] -> settings
      _ -> raise "settings table is corrupted"
    end
  end

  def update_settings(%Settings{} = settings, attrs) do
    with {:ok, settings} <- settings |> Settings.changeset(attrs) |> Repo.update(),
         :ok <- broadcast(settings) do
      {:ok, settings}
    end
  end

  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  def subscribe_to_changes do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic)
  end

  defp broadcast(settings) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, @topic, settings)
  end
end
