# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :teslamate,
  ecto_repos: [TeslaMate.Repo]

config :teslamate, TeslaMateWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Kz7vmP1gPYv/sogke6P3RP9uipMjOLhneQdbokZVx5gpLsNaN44TD20vtOWkMFIT",
  render_errors: [view: TeslaMateWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: TeslaMate.PubSub, adapter: Phoenix.PubSub.PG2]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{Mix.env()}.exs"
