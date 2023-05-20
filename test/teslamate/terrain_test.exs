defmodule TeslaMate.TerrainTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Terrain

  def start_terrain(name, responses \\ %{}) do
    log_name = :"log_#{name}"
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} = start_supervised({LogMock, name: log_name, pid: self(), last_update: nil})
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

      assert 42 == Terrain.get_elevation(name, {0, 0})
      assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 0, 0}}

      refute_receive _
    end

    @tag :capture_log
    test "return nil if an error occurred", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => fn -> {:error, :kaputt} end})

      assert Terrain.get_elevation(name, {0, 0}) == nil

      TestHelper.eventually(fn ->
        assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 0, 0}}
      end)

      refute_receive _
    end

    test "returns nil if the task takes longer than 100ms", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn ->
            Process.sleep(550)
            {:ok, 42}
          end
        })

      assert Terrain.get_elevation(name, {0, 0}) == nil

      TestHelper.eventually(fn ->
        assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 0, 0}}
      end)

      # still blocked
      assert Terrain.get_elevation(name, {0, 0}) == nil

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

      assert Terrain.get_elevation(name, {1, 1}) == nil

      TestHelper.eventually(fn ->
        assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 1, 1}}
      end)

      refute_receive _
    end

    @tag :capture_log
    test "breaks circuit if too many queries fail", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn -> {:error, :kaputt} end
        })

      assert Terrain.get_elevation(name, {0, 0}) == nil
      assert Terrain.get_elevation(name, {0, 0}) == nil
      assert Terrain.get_elevation(name, {0, 0}) == nil
      assert Terrain.get_elevation(name, {0, 0}) == nil
      assert Terrain.get_elevation(name, {0, 0}) == nil

      # circuit broke after 3 attempts
      TestHelper.eventually(
        fn ->
          assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 0, 0}}
          assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 0, 0}}
          assert_received {SRTM, {:get_elevation, %SRTM.Client{}, 0, 0}}
        end,
        attempts: 25
      )

      refute_receive _
    end
  end

  describe "handle_info/2" do
    test "handles :purge_srtm_in_memory_cache message", %{test: name} do
      :ok = start_terrain(name)

      send(name, :purge_srtm_in_memory_cache)

      refute_receive _
    end
  end
end
