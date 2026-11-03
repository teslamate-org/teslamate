defmodule TeslaMate.TerrainTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Terrain

  # An SRTM whose lookup raises, as on a corrupt cache file: at once, or once
  # the test sends :raise to the lookup.
  defmodule RaisingSRTM do
    def get_elevation({test, mode}, lat, lng, _opts) do
      send(test, {SRTM, {:get_elevation, lat, lng}, self()})

      if mode == :when_released do
        receive do
          :raise -> :ok
        end
      end

      raise "corrupt HGT file"
    end
  end

  defp start_raising_terrain(name, mode, timeout) do
    {:ok, _pid} =
      start_supervised(
        {Terrain, name: name, timeout: timeout, deps_srtm: {RaisingSRTM, {self(), mode}}}
      )

    Process.whereis(name)
  end

  # A lookup answers only once the test sends :answer to the SRTM mock.
  defp gated(answer) do
    fn ->
      receive do
        :answer -> answer
      end
    end
  end

  defp answer_lookup(name), do: send(Process.whereis(:"srtm_#{name}"), :answer)

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

  describe "a lookup that crashes" do
    @tag :capture_log
    test "fails like any other and leaves Terrain running", %{test: name} do
      # A timeout no crash outlasts: the lookup's own answer is the crash.
      terrain = start_raising_terrain(name, :at_once, 5_000)

      assert {:error, {%RuntimeError{message: "corrupt HGT file"}, _stacktrace}} =
               Terrain.get_elevation(name, {0, 0})

      assert {:error, {%RuntimeError{}, _stacktrace}} = Terrain.get_elevation(name, {0, 0})
      assert {:error, {%RuntimeError{}, _stacktrace}} = Terrain.get_elevation(name, {0, 0})

      # The circuit breaker blew after three failures.
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}
      assert Process.whereis(name) == terrain
    end

    @tag :capture_log
    test "fails like any other when it is slow", %{test: name} do
      terrain = start_raising_terrain(name, :when_released, 100)

      awaiting = Task.async(fn -> Terrain.await_elevation(name, {0, 0}) end)
      assert_receive {SRTM, {:get_elevation, 0, 0}, lookup}, 5_000

      # Terrain waits for the slow lookup.
      assert Terrain.get_elevation(name, {1, 1}) == {:error, :unavailable}

      send(lookup, :raise)

      assert {:error, {%RuntimeError{}, _stacktrace}} = Task.await(awaiting)
      assert Process.whereis(name) == terrain
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
      :ok = start_terrain(name, %{{0, 0} => gated({:ok, 42})})

      awaiting = Task.async(fn -> Terrain.await_elevation(name, {0, 0}) end)
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}, 5_000

      # Past the timeout, Terrain waits for the slow lookup.
      assert Terrain.get_elevation(name, {1, 1}) == {:error, :unavailable}

      answer_lookup(name)
      assert Task.await(awaiting) == {:ok, 42}

      refute_receive _
    end

    @tag :capture_log
    test "waits for a slow lookup that fails", %{test: name} do
      :ok = start_terrain(name, %{{1, 1} => gated({:error, :kaputt})})

      awaiting = Task.async(fn -> Terrain.await_elevation(name, {1, 1}) end)
      assert_receive {SRTM, {:get_elevation, 1, 1, _opts}}, 5_000
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}

      answer_lookup(name)
      assert Task.await(awaiting) == {:error, :kaputt}

      refute_receive _
    end

    test "waits for a slow lookup of get_elevation/1 to finish first", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => gated({:ok, 42}), {1, 1} => fn -> {:ok, 420} end})

      assert Terrain.get_elevation(name, {0, 0}) == {:error, :timeout}
      assert_received {SRTM, {:get_elevation, 0, 0, _opts}}

      awaiting = Task.async(fn -> Terrain.await_elevation(name, {1, 1}) end)

      # It cannot answer while the slow lookup holds Terrain.
      refute Task.yield(awaiting, 100)

      answer_lookup(name)
      assert Task.await(awaiting) == {:ok, 420}
      assert_received {SRTM, {:get_elevation, 1, 1, _opts}}

      refute_receive _
    end

    test "leaves get_elevation/1 unavailable while it waits for a slow lookup", %{test: name} do
      :ok = start_terrain(name, %{{0, 0} => gated({:ok, 42})})

      awaiting = Task.async(fn -> Terrain.await_elevation(name, {0, 0}) end)
      assert_receive {SRTM, {:get_elevation, 0, 0, _opts}}, 5_000

      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}

      answer_lookup(name)
      assert Task.await(awaiting) == {:ok, 42}

      refute_receive _
    end

    test "is unavailable when Terrain is not running", %{test: name} do
      assert Terrain.await_elevation(name, {0, 0}) == {:error, :unavailable}
    end

    test "is unavailable while disabled", %{test: name} do
      {:ok, _pid} = start_supervised({Terrain, name: name, disabled: true})

      assert Terrain.await_elevation(name, {0, 0}) == {:error, :unavailable}
      assert Terrain.get_elevation(name, {0, 0}) == {:error, :unavailable}
    end
  end
end
