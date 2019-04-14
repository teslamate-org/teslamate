defmodule TeslaMate.Mqtt do
  use Supervisor

  alias __MODULE__.{Publisher, PubSub}

  # API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    client_id = generate_client_id()

    children = [
      {Tortoise.Connection, config() ++ [client_id: client_id]},
      {Publisher, client_id: client_id},
      PubSub
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private

  defp config do
    auth = Application.get_env(:teslamate, :mqtt)

    [
      user_name: Keyword.get(auth, :username),
      password: Keyword.get(auth, :password),
      server: {Tortoise.Transport.Tcp, host: Keyword.get(auth, :host), port: 1883},
      handler: {Tortoise.Handler.Logger, []},
      subscriptions: []
    ]
  end

  defp generate_client_id do
    "TESLAMATE_" <> (:rand.uniform() |> to_string() |> Base.encode16() |> String.slice(0..10))
  end
end
