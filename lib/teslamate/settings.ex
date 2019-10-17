defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias __MODULE__.Settings
  alias TeslaMate.Log

  @topic inspect(__MODULE__)

  def get_settings! do
    case Repo.all(Settings) do
      [settings] -> settings
      _ -> raise "settings table is corrupted"
    end
  end

  def update_settings(%Settings{} = old_settings, attrs) do
    Repo.transaction(fn ->
      with {:ok, new_settings} <- old_settings |> Settings.changeset(attrs) |> Repo.update(),
           :ok <- on_range_change(old_settings, new_settings),
           :ok <- broadcast(new_settings) do
        new_settings
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  def subscribe_to_changes do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic)
  end

  defp on_range_change(%Settings{preferred_range: pf}, %Settings{preferred_range: pf}), do: :ok
  defp on_range_change(%Settings{}, %Settings{} = new), do: Log.recalculate_efficiencies(new)

  defp broadcast(settings) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, @topic, settings)
  end
end
