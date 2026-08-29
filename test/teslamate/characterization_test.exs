defmodule TeslaMate.CharacterizationTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Characterization

  test "at least one fixture exists" do
    assert Characterization.fixture_files() != []
  end

  for path <- Characterization.fixture_files() do
    test "replays #{Path.basename(path, ".json")}" do
      Characterization.run(unquote(path))
    end
  end
end
