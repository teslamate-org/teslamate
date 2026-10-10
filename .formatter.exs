# The Mix project lives in elixir/. Delegating there lets treefmt run
# `mix format` from the repository root; the formatter command sets
# MIX_EXS=elixir/mix.exs itself (see treefmt.toml and
# nix/flake-modules/formatter.nix).
[subdirectories: ["elixir"]]
