defmodule TeslaMate.BuildInfoTest do
  use ExUnit.Case, async: true

  alias TeslaMate.BuildInfo

  test "returns validated build metadata" do
    info =
      BuildInfo.current(
        version: "4.1.0-dev",
        config: [
          revision: "ABCDEF0123456789",
          ref: "feature/build-info",
          source: "example/teslamate",
          built_at: "2026-07-18T09:30:00Z"
        ]
      )

    assert info == %{
             version: "4.1.0-dev",
             revision: "abcdef0123456789",
             ref: "feature/build-info",
             source: "example/teslamate",
             built_at: "2026-07-18T09:30:00Z"
           }

    assert BuildInfo.metadata?(info)

    assert BuildInfo.log_line(info) ==
             "Build: source=example/teslamate ref=feature/build-info " <>
               "revision=abcdef0123456789 built_at=2026-07-18T09:30:00Z"
  end

  test "omits malformed or unsafe external values" do
    info =
      BuildInfo.current(
        version: "4.1.0-dev\nforged",
        config: %{
          revision: "not-a-revision",
          ref: "main\n[error] forged",
          source: "https://example.com/private",
          built_at: "yesterday"
        }
      )

    assert info == %{
             version: "unknown",
             revision: nil,
             ref: nil,
             source: nil,
             built_at: nil
           }

    refute BuildInfo.metadata?(info)
    assert BuildInfo.log_line(info) == "Version: unknown"
  end

  test "works for source builds without injected metadata" do
    info = BuildInfo.current(version: "4.1.0-dev", config: [])

    assert info.version == "4.1.0-dev"
    assert info.revision == nil
    assert info.ref == nil
    assert info.source == nil
    assert info.built_at == nil
    refute BuildInfo.metadata?(info)
  end
end
