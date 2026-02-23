defmodule TeslaMateWeb.Api.Auth.Plug do
  import Plug.Conn

  alias TeslaMateWeb.Api.Auth.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Token.verify_jwt(token) do
      assign(conn, :current_user, claims["sub"])
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid or missing authentication token"})
        |> halt()
    end
  end
end
