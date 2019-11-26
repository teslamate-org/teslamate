defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias __MODULE__.{GlobalSettings, CarSettings}
  alias TeslaMate.{Log, Locations}
  alias TeslaMate.Log.Car

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
    Repo.transaction(fn ->
      with {:ok, post} <- pre |> GlobalSettings.changeset(attrs) |> Repo.update(),
           :ok <- on_range_change(pre, post) do
        post
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_car_settings(%CarSettings{car: %Car{}} = pre, attrs) do
    Repo.transaction(fn ->
      with {:ok, post} <- pre |> CarSettings.changeset(attrs) |> Repo.update(),
           :ok <- on_sleep_mode_change(pre, post),
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

  defp on_sleep_mode_change(%CarSettings{sleep_mode_enabled: m}, %CarSettings{
         sleep_mode_enabled: m
       }) do
    :ok
  end

  defp on_sleep_mode_change(%CarSettings{}, %CarSettings{id: id}) do
    %Car{id: car_id} =
      Repo.one(from c in Car, select: [:id], where: c.settings_id == ^id, limit: 1)

    {:ok, %Postgrex.Result{num_rows: _rows}} =
      Repo.query("DELETE FROM geofence_sleep_mode_whitelist WHERE car_id = $1", [car_id])

    {:ok, %Postgrex.Result{num_rows: _rows}} =
      Repo.query("DELETE FROM geofence_sleep_mode_blacklist WHERE car_id = $1", [car_id])

    :ok = Locations.clear_cache()

    :ok
  end

  defp broadcast(car, settings) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, topic(car), settings)
  end
end
