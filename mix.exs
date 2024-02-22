defmodule TeslaMate.MixProject do
  use Mix.Project

  def project do
    [
      app: :teslamate,
      version: version(),
      description: build_info(),
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: releases(),
      deps: deps(),
      dialyzer: dialyzer(),
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
      {:castore, "~> 1.0"},
      {:ecto_sql, "~> 3.0"},
      {:ex_cldr, "~> 2.37.0"},
      {:ex_cldr_plugs, "~> 1.0"},
      {:excoveralls, "~> 0.10", only: :test},
      {:finch, "~> 0.3"},
      {:floki, "~> 0.23"},
      {:fuse, "~> 2.4"},
      {:gen_state_machine, "~> 3.0"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:mock, "~> 0.3", only: :test},
      {:nimble_csv, "~> 1.1"},
      {:phoenix, "~> 1.6.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.17.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:plug_cowboy, "~> 2.0"},
      {:postgrex, ">= 0.0.0"},
      {:ranch, "~> 2.1", override: true},
      {:srtm, "~> 0.8.0"},
      {:tesla, "~> 1.4"},
      {:timex, "~> 3.0"},
      {:tortoise, "~> 0.10"},
      {:tzdata, "~> 1.1"},
      {:websockex, "~> 0.4"},
      {:cloak_ecto, "~> 1.2"},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:credo, "~> 1.7.1", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd --cd assets npm ci --no-audit --loglevel=error"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.deploy": ["cmd --cd assets npm run deploy", "phx.digest"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test --no-start"],
      ci: ["format --check-formatted", "deps.unlock --check-unused", "test --raise"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_core_path: "priv/plts/",
      plt_add_apps: [:mix, :ex_unit],
      plt_ignore_apps: [],
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end

  defp releases do
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

  def build_info do
    # get info on remote, will help locate origin for PR builds
    remote_output =
      case System.cmd(
             "git",
             ["remote", "get-url", "origin"],
             stderr_to_stdout: true
           ) do
        {remote_output, _} -> remote_output |> to_string()
        _ -> "no git remote output"
      end

    # get info on the branch
    log_output =
      case System.cmd(
             "git",
             ["log", "-1", "--format=rev:%h %ad %d"],
             stderr_to_stdout: true
           ) do
        {log_output, _} -> log_output |> to_string()
        _ -> "no git log output"
      end

    # get date which will be build date and time
    build_date =
      case System.cmd("date", ~w[], stderr_to_stdout: true) do
        {build_date, _} -> build_date |> to_string()
        _ -> "no date"
      end

    concatenated_output =
      String.trim(remote_output) <>
        " " <> String.trim(log_output) <> ", build date: " <> String.trim(build_date)

    concatenated_output
  end
end
