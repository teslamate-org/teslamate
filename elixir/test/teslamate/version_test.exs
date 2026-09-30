defmodule TeslaMate.VersionTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Version

  # Fails on a build that compiled an older VERSION: the project config is
  # read from VERSION when the test run starts.
  test "is the version of the project and of the loaded application" do
    assert Version.version() == Mix.Project.config()[:version]
    assert Version.version() == to_string(Application.spec(:teslamate, :vsn))
  end

  # Any other module that compiles the project version in keeps a stale copy
  # after a VERSION bump.
  test "is the only module in lib that reads the project config" do
    lib = Path.expand("../../lib", __DIR__)

    readers =
      for path <- Path.wildcard(Path.join(lib, "**/*.{ex,heex}")),
          File.read!(path) =~ "Mix.Project",
          do: Path.relative_to(path, lib)

    assert readers == ["teslamate/version.ex"]
  end
end
