defmodule TeslaMate.TerrainTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Terrain

  def start_terrain(name, responses \\ %{}) do
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} = start_supervised({SRTMMock, name: srtm_name, pid: self(), responses: responses})

    opts = [name: name, timeout: 500, deps_srtm: {SRTMMock, srtm_name}]

    {:ok, _pid} = start_supervised({Terrain, opts})

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

    test "returns a timeout instead of exiting when Terrain does not answer in time",
         %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => fn -> {:ok, 42} end})
      pid = Process.whereis(name)

      :ok = :sys.suspend(pid)
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :timeout}
      :ok = :sys.resume(pid)

      # Terrain still answers the call, too late: the answer is dropped.
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}
      refute_receive _
    end

    test "returns unavailable when Terrain is not running", %{test: name} do
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}
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

  describe "await_elevation/1" do
    test "returns the elevation", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => fn -> {:ok, 42} end})

      assert {:ok, 42} == Terrain.await_elevation(name, {0, 0})
      assert_received {SRTM, {:get_elevation, 0, 0, [disk_cache_path: ".srtm_cache"]}}

      refute_receive _
    end

    test "waits for a lookup that takes longer than the timeout", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn ->
            Process.sleep(550)
            {:ok, 42}
          end
        })

      assert Terrain.await_elevation(name, {0, 0}) == {:ok, 42}
      assert_received {SRTM, {:get_elevation, 0, 0, _opts}}

      refute_receive _
    end

    @tag :capture_log
    test "waits for a slow lookup that fails", %{test: name} do
      :ok =
        start_terrain(name, %{
          {1, 1} => fn ->
            Process.sleep(550)
            {:error, :kaputt}
          end
        })

      assert Terrain.await_elevation(name, {1, 1}) == {:error, :kaputt}
      assert_received {SRTM, {:get_elevation, 1, 1, _opts}}

      refute_receive _
    end

    test "waits for a slow lookup of get_elevation/1 to finish first", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn ->
            Process.sleep(550)
            {:ok, 42}
          end,
          {1, 1} => fn -> {:ok, 420} end
        })

      assert Terrain.get_elevation(name, {0, 0}) == {:error, :timeout}
      assert Terrain.await_elevation(name, {1, 1}) == {:ok, 420}

      assert_received {SRTM, {:get_elevation, 0, 0, _opts}}
      assert_received {SRTM, {:get_elevation, 1, 1, _opts}}

      refute_receive _
    end

    test "leaves get_elevation/1 unavailable while it waits for a slow lookup", %{test: name} do
      :ok =
        start_terrain(name, %{
          {0, 0} => fn ->
            Process.sleep(550)
            {:ok, 42}
          end
        })

      awaiting = Task.async(fn -> Terrain.await_elevation(name, {0, 0}) end)
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}

      TestHelper.eventually(fn ->
        assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}
      end)

      assert Task.await(awaiting) == {:ok, 42}

      refute_receive _
    end

    test "is unavailable while disabled", %{test: name} do
      {:ok, _pid} = start_supervised({Terrain, name: name, disabled: true})

      assert Terrain.await_elevation(name, {0, 0}) == {:error, :unavailable}
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}
    end
  end
end
