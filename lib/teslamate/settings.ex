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
    from(s in CarSettings,
      join: c in assoc(s, :car),
      order_by: [asc: fragment("COALESCE(?, ?)", c.display_priority, c.id), asc: c.id],
      preload: [car: c]
    )
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

  def move_car(%CarSettings{car: %Car{id: car_id}} = settings, direction)
      when direction in [:up, :down] do
    cars = ordered_cars()
    ordered_ids = Enum.map(cars, & &1.id)

    reordered_ids =
      case Enum.find_index(ordered_ids, &(&1 == car_id)) do
        nil ->
          ordered_ids

        index ->
          swap_index =
            case direction do
              :up -> index - 1
              :down -> index + 1
            end

          if swap_index in 0..(length(ordered_ids) - 1) do
            swap(ordered_ids, index, swap_index)
          else
            ordered_ids
          end
      end

    with {:ok, updated_cars} <- persist_car_order(cars, reordered_ids) do
      Enum.each(updated_cars, &broadcast_car/1)
      {:ok, updated_car(updated_cars, settings.car)}
    end
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

  defp broadcast_car(%Car{} = car) do
    Phoenix.PubSub.broadcast(TeslaMate.PubSub, topic(car), {:car_updated, car})
  rescue
    _ -> :ok
  end

  defp ordered_cars do
    from(c in Car,
      order_by: [asc: fragment("COALESCE(?, ?)", c.display_priority, c.id), asc: c.id],
      preload: [:settings]
    )
    |> Repo.all()
  end

  defp persist_car_order(cars, ordered_ids) do
    cars_by_id = Map.new(cars, &{&1.id, &1})

    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index(1)
      |> Enum.reduce([], fn {id, priority}, acc ->
        car = Map.fetch!(cars_by_id, id)

        case car.display_priority do
          ^priority ->
            [car | acc]

          _ ->
            case Log.update_car(car, %{display_priority: priority}, preload: [:settings]) do
              {:ok, updated_car} -> [updated_car | acc]
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp updated_car(cars, %Car{id: car_id}) do
    Enum.find(cars, &(&1.id == car_id))
  end

  defp swap(ids, left, right) do
    left_id = Enum.at(ids, left)
    right_id = Enum.at(ids, right)

    ids
    |> List.replace_at(left, right_id)
    |> List.replace_at(right, left_id)
  end
end
