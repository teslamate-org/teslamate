defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias __MODULE__.{GlobalSettings, CarSettings}
  alias TeslaMate.{Log, Locations, Mutex, Vehicles}
  alias TeslaMate.Log.Car
  import Core.Dependency, only: [call: 2]

  def get_global_settings! do
    case Repo.all(GlobalSettings) do
      [settings] -> settings
      _ -> raise "settings table is corrupted"
    end
  end

  def get_car_settings do
    from(s in CarSettings,
      join: c in assoc(s, :car),
      order_by: [asc: c.display_priority, asc: c.id],
      preload: [car: c]
    )
    |> Repo.all()
  end

  def get_car_settings!(%Car{settings_id: id}) do
    CarSettings
    |> Repo.get!(id)
    |> Repo.preload(:car)
  end

  # Serializes language changes. Each one reads all addresses and writes only
  # what differs from what it read: two at once could leave addresses in the
  # other language. Serialized, the last change wins and Nominatim gets one
  # stream of requests.
  @language_change __MODULE__.LanguageChange

  def language_change_mutex, do: @language_change

  @doc """
  Updates the global settings.

  Changing the language fetches all addresses in the new language before
  anything is written, and then writes the settings together with the
  addresses: all of it or nothing.
  """
  def update_global_settings(%GlobalSettings{} = pre, attrs) do
    case GlobalSettings.changeset(pre, attrs) do
      %Ecto.Changeset{valid?: true, changes: %{language: lang}} = changeset ->
        Mutex.run(@language_change, fn -> change_language(pre, changeset, lang) end)

      changeset ->
        save_global_settings(pre, changeset, [])
    end
  end

  # Reads the addresses only once it is its turn
  defp change_language(pre, changeset, lang) do
    with {:ok, addresses} <- Locations.fetch_localized_addresses(lang) do
      save_global_settings(pre, changeset, addresses)
    end
  end

  # Returns the settings as saved, read back: `pre` may be outdated by changes
  # saved meanwhile, e.g. from another tab or during a language change.
  defp save_global_settings(pre, changeset, addresses) do
    Repo.transaction(fn ->
      with {:ok, post} <- Repo.update(changeset),
           :ok <- on_range_change(pre, post),
           :ok <- Locations.update_addresses(addresses) do
        Repo.reload!(post)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_car_settings(%CarSettings{car: %Car{}} = pre, attrs) do
    Repo.transaction(fn ->
      with {:ok, post} <- pre |> CarSettings.changeset(attrs) |> Repo.update(),
           :ok <- on_enabled_change(pre, post),
           :ok <- broadcast(pre.car, post) do
        post
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change_global_settings(%GlobalSettings{} = settings, attrs \\ %{}) do
    GlobalSettings.changeset(settings, attrs)
  end

  def change_car_settings(%CarSettings{} = car_settings, attrs \\ %{}) do
    CarSettings.changeset(car_settings, attrs)
  end

  def topic(%Car{id: id}), do: inspect(CarSettings) <> to_string(id)

  def subscribe_to_changes(car) do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, topic(car))
  end

  defp on_range_change(%GlobalSettings{preferred_range: pf}, %GlobalSettings{preferred_range: pf}) do
    :ok
  end

  defp on_range_change(%GlobalSettings{}, %GlobalSettings{} = new) do
    Log.recalculate_efficiencies(new)
  end

  def on_enabled_change(%CarSettings{enabled: preEnabled}, %CarSettings{enabled: postEnabled}) do
    if preEnabled != postEnabled do
      call(Vehicles, :restart)
    end

    :ok
  end

  defp broadcast(car, settings) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, topic(car), settings)
  rescue
    _ -> :ok
  end
end
