defmodule TeslaMate.MixProject do
  use Mix.Project

  def project do
    [
      app: :teslamate,
      version: version(),
      elixir: "~> 1.11",
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
      {:phoenix, "~> 1.5.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:gen_state_machine, "~> 2.0"},
      {:ecto_enum, "~> 1.0"},
      {:phoenix_live_view, "~> 0.1"},
      {:floki, "~> 0.23", only: :test},
      {:tortoise, "== 0.9.4"},
      {:excoveralls, "~> 0.10", only: :test},
      {:srtm, "~> 0.5"},
      {:fuse, "~> 2.4"},
      {:mock, "~> 0.3", only: :test},
      {:castore, "~> 0.1"},
      {:ex_cldr, "~> 2.0"},
      {:nimble_csv, "~> 1.1"},
      {:timex, "~> 3.0"},
      {:websockex, "~> 0.4"},
      {:tzdata, "~> 1.0"},
      {:finch, "~> 0.3"}
    ]
  end

  defp aliases do
    [
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

  defp version do
    case File.read("VERSION") do
      {:ok, version} -> String.trim(version)
      {:error, _reason} -> "0.0.0"
    end
  end
end
