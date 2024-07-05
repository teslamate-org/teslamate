defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias __MODULE__.{GlobalSettings, CarSettings}
  alias TeslaMate.{Log, Locations, Vehicles}
  alias TeslaMate.Log.Car
  import Core.Dependency, only: [call: 2]

  def get_global_settings! do
    case Repo.all(GlobalSettings) do
      [settings] -> settings
      _ -> raise "settings table is corrupted"
    end
  end

  def get_car_settings do
    from(s in CarSettings, order_by: s.id, preload: [:car])
    |> Repo.all()
  end

  def get_car_settings!(%Car{settings_id: id}) do
    CarSettings
    |> Repo.get!(id)
    |> Repo.preload(:car)
  end

  def update_global_settings(%GlobalSettings{} = pre, attrs) do
    Repo.transaction(
      fn ->
        with {:ok, post} <- pre |> GlobalSettings.changeset(attrs) |> Repo.update(),
             :ok <- on_range_change(pre, post),
             :ok <- on_language_change(pre, post) do
          post
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: 60_000
    )
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

  defp on_language_change(%GlobalSettings{language: l}, %GlobalSettings{language: l}) do
    :ok
  end

  defp on_language_change(%GlobalSettings{}, %GlobalSettings{language: lang}) do
    Locations.refresh_addresses(lang)
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
