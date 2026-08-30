defmodule TeslaMate.CharacterizationTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Characterization

  test "no orphaned goldens" do
    assert Characterization.orphans() == []
  end

  test "a declared only: target exists" do
    assert Characterization.only_target_error() == nil
  end

  for pair <- Characterization.pairs() do
    prefix = if pair.selftest?, do: "selftest ", else: ""

    test "replays #{prefix}#{pair.name}" do
      Characterization.run(unquote(Macro.escape(pair)))
    end
  end
end
