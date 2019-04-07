# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,
  default_release: :default,
  default_environment: :prod

# For a full list of config options for both releases
# and environments, visit https://hexdocs.pm/distillery/config/distillery.html

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(cookie: "${ERLANG_COOKIE}")
  set(pre_start_hooks: "rel/pre_start_hooks")
  set(vm_args: "rel/vm.args")
end

release :teslamate do
  set(version: current_version(:teslamate))

  set(
    applications: [
      :runtime_tools
    ]
  )

  set(
    config_providers: [
      {Mix.Releases.Config.Providers.Elixir, ["${RELEASE_ROOT_DIR}/etc/config.exs"]}
    ]
  )

  set(
    overlays: [
      {:copy, "rel/config/config.exs", "etc/config.exs"}
    ]
  )
end
