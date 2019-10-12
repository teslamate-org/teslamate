defmodule TeslaMate.MixProject do
  use Mix.Project

  def project do
    [
      app: :teslamate,
      version: "1.11.0",
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: releases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        ci: :test
      ]
    ]
  end

  def application do
    [
      mod: {TeslaMate.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Default
      {:phoenix, "~> 1.4"},
      {:phoenix_pubsub, "~> 1.1"},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      # Custom
      {:tesla_api, github: "adriankumpf/tesla_api", branch: "v10"},
      {:gen_state_machine, "~> 2.0"},
      {:ecto_enum, "~> 1.2"},
      {:phoenix_live_view, "~> 0.1"},
      {:floki, ">= 0.0.0", only: :test},
      {:tortoise, "~> 0.9"},
      {:excoveralls, "~> 0.10", only: :test},
      {:mojito, "~> 0.5"},
      {:srtm, "~> 0.2"},
      {:fuse, "~> 2.4"},
      {:mock, "~> 0.3", only: :test},
      {:castore, "~> 0.1"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", &setup_yarn/1],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test --no-start"],
      ci: ["format --check-formatted", "test --raise"]
    ]
  end

  defp releases() do
    [
      teslamate: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  defp setup_yarn(_) do
    cmd("yarn", ["install"], cd: "assets")
  end

  defp cmd(cmd, args, opts) do
    opts = Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)
    {_, result} = System.cmd(cmd, args, opts)

    if result != 0 do
      raise "Non-zero result (#{result}) from: #{cmd} #{Enum.map_join(args, " ", &inspect/1)}"
    end
  end
end
