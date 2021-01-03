defmodule TeslaMate.Mqtt do
  use Supervisor

  alias __MODULE__.{Publisher, PubSub, Handler}

  # API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    client_id = generate_client_id()

    children = [
      {Tortoise.Connection, connection_config(opts) ++ [client_id: client_id]},
      {Publisher, client_id: client_id},
      {PubSub, namespace: opts[:namespace]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private

  alias Tortoise.Transport

  defp connection_config(opts) do
    socket_opts =
      if opts[:ipv6],
        do: [:inet6],
        else: []

    server =
      if opts[:tls] do
        verify =
          if opts[:accept_invalid_certs],
            do: :verify_none,
            else: :verify_peer

        {Transport.SSL,
         host: opts[:host],
         port: opts[:port] || 8883,
         cacertfile: CAStore.file_path(),
         verify: verify,
         opts: socket_opts}
      else
        {Transport.Tcp, host: opts[:host], port: opts[:port] || 1883, opts: socket_opts}
      end

    [
      user_name: opts[:username],
      password: opts[:password],
      server: server,
      handler: {Handler, []},
      subscriptions: []
    ]
  end

  defp generate_client_id do
    "TESLAMATE_" <> (:rand.uniform() |> to_string() |> Base.encode16() |> String.slice(0..10))
  end
end
