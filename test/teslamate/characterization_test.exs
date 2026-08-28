defmodule TeslaMate.CharacterizationTest do
  use ExUnit.Case, async: false

  alias TeslaMate.Characterization

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TeslaMate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "at least one fixture exists" do
    assert Characterization.fixture_files() != []
  end

  for path <- Characterization.fixture_files() do
    test "replays #{Path.basename(path, ".json")}" do
      Characterization.run(unquote(path))
    end
  end
end
