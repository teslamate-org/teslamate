defmodule TeslaMateWeb.Plugs.OperationsAuth do
  @moduledoc """
  Protects the operations surface when sensitive capabilities are enabled.

  Authentication remains optional while the page is read-only and does not
  expose logs. Runtime configuration requires credentials before enabling
  either sensitive capability.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    config = Keyword.get(opts, :config, Application.get_env(:teslamate, :operations_auth, []))
    conn = put_resp_header(conn, "cache-control", "no-store")

    if get_value(config, :required, false) do
      authenticate(conn, config)
    else
      conn
    end
  end

  defp authenticate(conn, config) do
    with username when is_binary(username) and username != "" <- get_value(config, :username),
         password when is_binary(password) and password != "" <- get_value(config, :password) do
      Plug.BasicAuth.basic_auth(conn,
        username: username,
        password: password,
        realm: "TeslaMate Operations"
      )
    else
      _ ->
        conn
        |> send_resp(:service_unavailable, "Operations authentication is not configured")
        |> halt()
    end
  end

  defp get_value(source, key, default \\ nil)
  defp get_value(source, key, default) when is_list(source), do: Keyword.get(source, key, default)
  defp get_value(source, key, default) when is_map(source), do: Map.get(source, key, default)
  defp get_value(_source, _key, default), do: default
end
