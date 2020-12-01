defmodule TeslaMate.Mqtt do
  use Supervisor

  alias __MODULE__.{Publisher, PubSub, Handler}

  # API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    client_id = generate_client_id()

    children = [
      {Tortoise.Connection, connection_config() ++ [client_id: client_id]},
      {Publisher, client_id: client_id},
      {PubSub, namespace: namespace()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private

  alias Tortoise.Transport

  defp connection_config do
    opts = Application.get_env(:teslamate, :mqtt)
    host = Keyword.get(opts, :host)

    socket_opts =
      if opts[:ipv6] do
        [:inet6]
      else
        []
      end

    server =
      if Keyword.get(opts, :tls) == "true" do
        verify =
          if Keyword.get(opts, :accept_invalid_certs) == "true" do
            :verify_none
          else
            :verify_peer
          end

        {Transport.SSL,
         host: host,
         port: 8883,
         cacertfile: CAStore.file_path(),
         verify: verify,
         opts: socket_opts}
      else
        {Transport.Tcp, host: host, port: 1883, opts: socket_opts}
      end

    [
      user_name: Keyword.get(opts, :username),
      password: Keyword.get(opts, :password),
      server: server,
      handler: {Handler, []},
      subscriptions: []
    ]
  end

  defp namespace do
    Application.get_env(:teslamate, :mqtt) |> Keyword.get(:namespace)
  end

  defp generate_client_id do
    "TESLAMATE_" <> (:rand.uniform() |> to_string() |> Base.encode16() |> String.slice(0..10))
  end
end
