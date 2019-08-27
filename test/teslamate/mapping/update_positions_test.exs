defmodule TeslaMate.Mapping.UpdatePositionsTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log.{Car, Position}
  alias TeslaMate.{Log, Mapping}

  defp start_mapping(name, responses) do
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} = start_supervised({SRTMMock, name: srtm_name, pid: self(), responses: responses})

    {:ok, _} = start_supervised({Mapping, name: name, deps_srtm: {SRTMMock, srtm_name}})

    :ok
  end

  test "return the elevation", %{test: name} do
    assert %Car{id: car_id} = car_fixture()

    positions =
      %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      |> List.duplicate(201)
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(car_id, position)
        pos
      end)

    :ok = start_mapping(name, %{{0.0, 0.0} => fn -> {:ok, 42} end})

    for _ <- positions do
      assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 0.0, 0.0}}
    end

    for position <- positions do
      assert %Position{elevation: 42.0} = TeslaMate.Repo.get(Position, position.id)
    end

    refute_receive _
  end

  @tag :capture_log
  test "handles errors during update", %{test: name} do
    assert %Car{id: car_id} = car_fixture()

    [p0, p1, p2] =
      [
        %{date: DateTime.utc_now(), latitude: 0, longitude: 0},
        %{date: DateTime.utc_now(), latitude: 99, longitude: 99},
        %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      ]
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(car_id, position)
        pos
      end)

    :ok =
      start_mapping(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {99.0, 99.0} => fn -> {:error, :kaputt} end
      })

    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 0.0, 0.0}}
    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 99.0, 99.0}}
    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 0.0, 0.0}}

    :timer.sleep(10)

    assert %Position{elevation: 42.0} = TeslaMate.Repo.get(Position, p0.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p1.id)
    assert %Position{elevation: 42.0} = TeslaMate.Repo.get(Position, p2.id)

    refute_receive _
  end

  test "reacts to :add_elevation_to_positions messages", %{test: name} do
    assert %Car{id: car_id} = car_fixture()

    :ok = start_mapping(name, %{{0.0, 0.0} => fn -> {:ok, 42} end})

    refute_receive _, 40

    positions =
      %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      |> List.duplicate(5)
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(car_id, position)
        pos
      end)

    send(name, :add_elevation_to_positions)

    for _ <- positions do
      assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 0.0, 0.0}}
    end

    for position <- positions do
      assert %Position{elevation: 42.0} = TeslaMate.Repo.get(Position, position.id)
    end

    refute_receive _
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42})
      |> Log.create_car()

    car
  end
end
