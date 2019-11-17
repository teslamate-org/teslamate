defmodule TeslaMate.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias __MODULE__.{GlobalSettings, CarSettings}
  alias TeslaMate.Log.Car
  alias TeslaMate.Log

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

  def update_car_settings(%CarSettings{car: %Car{}} = settings, attrs) do
    Repo.transaction(fn ->
      with {:ok, post} <- settings |> CarSettings.changeset(attrs) |> Repo.update(),
           :ok <- broadcast(settings.car, post) do
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

  defp on_range_change(%GlobalSettings{preferred_range: pf}, %GlobalSettings{preferred_range: pf}),
    do: :ok

  defp on_range_change(%GlobalSettings{}, %GlobalSettings{} = new),
    do: Log.recalculate_efficiencies(new)

  defp broadcast(car, settings) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, topic(car), settings)
  end
end
