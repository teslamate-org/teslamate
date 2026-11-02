defmodule TeslaMate.TerrainTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Terrain
  alias TeslaMate.Log.Position

  def start_terrain(name, responses \\ %{}, positions_without_elevation \\ []) do
    log_name = :"log_#{name}"
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} =
      start_supervised(
        {LogMock,
         name: log_name,
         pid: self(),
         last_update: nil,
         positions_without_elevation: positions_without_elevation}
      )

    {:ok, _pid} = start_supervised({SRTMMock, name: srtm_name, pid: self(), responses: responses})

    opts = [
      name: name,
      timeout: 500,
      deps_log: {LogMock, log_name},
      deps_srtm: {SRTMMock, srtm_name}
    ]

    {:ok, _} = start_supervised({Terrain, opts})
    assert_receive {:get_positions_without_elevation, 0}

    :ok
  end

  describe "get_elevation/1" do
    test "return the elevation", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => fn -> {:ok, 42} end})

      assert {:ok, 42} == Terrain.get_elevation(name, {0, 0})
      assert_received {SRTM, {:get_elevation, 0, 0, [disk_cache_path: ".srtm_cache"]}}

      refute_receive _
    end

    @tag :capture_log
    test "returns nil where the terrain has no data", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => fn -> {:ok, nil} end})

      assert {:ok, nil} == Terrain.get_elevation(name, {0, 0})
      assert_received {SRTM, {:get_elevation, 0, 0, _opts}}

      refute_receive _
    end

    @tag :capture_log
    test "returns the error if an error occurred", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => fn -> {:error, :kaputt} end})

      assert Terrain.get_elevation(name, {0, 0}) == {:error, :kaputt}

      TestHelper.eventually(fn ->
        assert_received {SRTM, {:get_elevation, 0, 0, _opts}}
      end)

      refute_receive _
    end

    test "returns a timeout if the task takes longer than 100ms", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn ->
            Process.sleep(550)
            {:ok, 42}
          end
        })

      assert Terrain.get_elevation(name, {0, 0}) == {:error, :timeout}

      TestHelper.eventually(fn ->
        assert_received {SRTM, {:get_elevation, 0, 0, _opts}}
      end)

      # still blocked
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}

      refute_receive _, 300
    end

    @tag :capture_log
    test "handles long running tasks that return with an error", %{test: name} do
      :ok =
        start_terrain(name, %{
          {1, 1} => fn ->
            Process.sleep(101)
            {:error, :kaputt}
          end
        })

      assert Terrain.get_elevation(name, {1, 1}) == {:error, :kaputt}

      TestHelper.eventually(fn ->
        assert_received {SRTM, {:get_elevation, 1, 1, _opts}}
      end)

      refute_receive _
    end

    @tag :capture_log
    test "breaks circuit if too many queries fail", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn -> {:error, :kaputt} end
        })

      assert Terrain.get_elevation(name, {0, 0}) == {:error, :kaputt}
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :kaputt}
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :kaputt}
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}

      # circuit broke after 3 attempts
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}, 1_000
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}, 1_000
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}, 1_000

      refute_receive _
    end
  end

  describe "adding the elevation to positions" do
    defp position(id, drive_id, {lat, lng}) do
      %Position{
        id: id,
        drive_id: drive_id,
        latitude: Decimal.new(lat),
        longitude: Decimal.new(lng)
      }
    end

    @tag :capture_log
    test "recomputes each drive it added elevation to once", %{test: name} do
      :ok =
        start_terrain(
          name,
          %{
            {0.0, 0.0} => fn -> {:ok, 42} end,
            {1.0, 1.0} => fn -> {:ok, nil} end,
            {2.0, 2.0} => fn -> {:error, :kaputt} end
          },
          [
            position(1, 10, {0, 0}),
            position(2, 20, {0, 0}),
            position(3, 10, {0, 0}),
            position(4, 30, {1, 1}),
            position(5, 40, {2, 2})
          ]
        )

      for id <- 1..3 do
        assert_receive {:update_position, %Position{id: ^id}, %{elevation: 42}}
      end

      assert_receive {:update_position, %Position{id: 4}, %{elevation: nil}}
      assert_receive {:update_drive_elevation, 10}
      assert_receive {:update_drive_elevation, 20}
      assert_receive {:get_positions_without_elevation, 5}

      refute_received {:update_position, %Position{id: 5}, _attrs}
      refute_received {:update_drive_elevation, _drive_id}
    end

    test "recomputes the drives after the positions of the page are updated", %{test: name} do
      :ok =
        start_terrain(name, %{{0.0, 0.0} => fn -> {:ok, 42} end}, [
          position(1, 10, {0, 0}),
          position(2, 10, {0, 0})
        ])

      assert_receive {:get_positions_without_elevation, 2}

      {:messages, messages} = Process.info(self(), :messages)

      assert [
               {:update_position, %Position{id: 1}, %{elevation: 42}},
               {:update_position, %Position{id: 2}, %{elevation: 42}},
               {:update_drive_elevation, 10}
             ] = Enum.reject(messages, &match?({SRTM, _}, &1))
    end
  end
end
