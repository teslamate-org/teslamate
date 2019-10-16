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

  alias Tortoise.Transport

  defp config do
    auth = Application.get_env(:teslamate, :mqtt)
    host = Keyword.get(auth, :host)

    server =
      if Keyword.get(auth, :tls) == "true" do
        verify =
          if Keyword.get(auth, :accept_invalid_certs) == "true" do
            :verify_none
          else
            :verify_peer
          end

        {Transport.SSL, host: host, port: 8883, cacertfile: CAStore.file_path(), verify: verify}
      else
        {Transport.Tcp, host: host, port: 1883}
      end

    [
      user_name: Keyword.get(auth, :username),
      password: Keyword.get(auth, :password),
      server: server,
      handler: {Tortoise.Handler.Logger, []},
      subscriptions: []
    ]
  end

  defp generate_client_id do
    "TESLAMATE_" <> (:rand.uniform() |> to_string() |> Base.encode16() |> String.slice(0..10))
  end
end
