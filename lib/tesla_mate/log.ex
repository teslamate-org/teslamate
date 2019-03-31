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

        with :ok <- close_state(last_position_id) do
          create_state(%{
            state: state,
            start_date: DateTime.utc_now(),
            start_pos: last_position_id
          })
        end

      nil ->
        last_position_id = get_last_position_id!()

        create_state(%{state: state, start_date: DateTime.utc_now(), start_pos: last_position_id})
    end
  end

  def close_state(position_id) do
    end_date = DateTime.utc_now()

    result =
      State
      |> where([s], is_nil(s.end_date))
      |> update(set: [end_date: ^end_date, end_pos: ^position_id])
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
end
