defmodule TeslaMate.Log do
  @moduledoc """
  The Log context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  alias TeslaMate.Log.Position

  def insert_position(attrs \\ %{}) do
    %Position{}
    |> Position.changeset(attrs)
    |> Repo.insert()
  end

  def get_last_position_id! do
    Position
    |> select([p], max(p.id))
    |> Repo.one!()
  end

  alias TeslaMate.Log.State

  def start_state(state) do
    case get_current_state() do
      %{state: ^state} ->
        :ok

      %{state: _state} ->
        last_position_id = get_last_position_id!()

        attrs = %{
          state: state,
          start_date: DateTime.utc_now(),
          start_position_id: last_position_id
        }

        with :ok <- close_state(last_position_id),
             {:ok, _} <- create_state(attrs) do
          :ok
        end

      nil ->
        last_position_id = get_last_position_id!()

        attrs = %{
          state: state,
          start_date: DateTime.utc_now(),
          start_position_id: last_position_id
        }

        with {:ok, _} <- create_state(attrs) do
          :ok
        end
    end
  end

  def close_state(position_id) do
    end_date = DateTime.utc_now()

    result =
      State
      |> where([s], is_nil(s.end_date))
      |> update(set: [end_date: ^end_date, end_position_id: ^position_id])
      |> Repo.update_all([])

    case result do
      {0, nil} -> {:erorr, :no_state_to_be_closed}
      {1, nil} -> :ok
      {n, nil} -> {:error, {:closed_multiple_states, n}}
    end
  end

  def get_current_state do
    State
    |> select([:state])
    |> where([s], is_nil(s.end_date))
    |> Repo.one()
  end

  defp create_state(attrs \\ %{}) do
    %State{}
    |> State.changeset(attrs)
    |> Repo.insert()
  end

  defp update_state(%State{} = state, attrs) do
    state
    |> State.changeset(attrs)
    |> Repo.update()
  end

  alias TeslaMate.Log.DriveState

  def start_drive_state do
    last_position_id = get_last_position_id!()
    attrs = %{start_date: DateTime.utc_now(), start_position_id: last_position_id}

    with {:ok, _} <- create_drive_state(attrs) do
      :ok
    end
  end

  def close_drive_state do
    start_position_id =
      case get_last_drive_state() do
        %{start_position_id: start_position_id} -> start_position_id
        # Assumption there is always one position with id 1
        nil -> 1
      end

    end_date = DateTime.utc_now()
    last_position_id = get_last_position_id!()

    result =
      DriveState
      |> where([s], is_nil(s.end_date))
      |> update(set: [end_date: ^end_date, end_position_id: ^last_position_id])
      |> Repo.update_all([])
      |> case do
        {0, nil} -> {:erorr, :no_state_to_be_closed}
        {1, nil} -> :ok
        {n, nil} -> {:error, {:closed_multiple_states, n}}
      end

    with :ok <- result do
      if start_position_id != 1 do
        :ok = update_drive_statistics(start_position_id, last_position_id)
      end

      :ok
    end
  end

  def get_last_drive_state do
    DriveState
    |> select([:start_position_id])
    |> where([d], is_nil(d.end_date))
    |> Repo.one()
  end

  defp update_drive_statistics(start_position_id, end_position_id) do
    statistics =
      Position
      |> select([p], %{
        outside_temp_avg: fragment("?::float", avg(p.outside_temp)),
        speed_max: max(p.speed),
        speed_min: min(p.speed),
        power_max: max(p.power),
        power_min: min(p.power),
        power_avg: fragment("?::float", avg(p.power))
      })
      |> where([p], ^start_position_id <= p.id and p.id <= ^end_position_id)
      |> Repo.one!()
      |> Map.to_list()

    result =
      DriveState
      |> where(
        [d],
        d.start_position_id == ^start_position_id and d.end_position_id == ^end_position_id
      )
      |> update(set: ^statistics)
      |> Repo.update_all([])

    case result do
      {0, nil} -> {:erorr, :no_drive_states_to_be_updated}
      {1, nil} -> :ok
    end
  end

  defp create_drive_state(attrs \\ %{}) do
    %DriveState{}
    |> DriveState.changeset(attrs)
    |> Repo.insert()
  end

  defp update_drive_state(%DriveState{} = drive_state, attrs) do
    drive_state
    |> DriveState.changeset(attrs)
    |> Repo.update()
  end
end
