defmodule TeslaMateWeb.Api.EnableApiPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:teslamate, :api)[:enabled] do
      true ->
        conn

      _ ->
        conn
        |> put_status(:not_found)
        |> Phoenix.Controller.json(%{error: "API is not enabled"})
        |> halt()
    end
  end
end
