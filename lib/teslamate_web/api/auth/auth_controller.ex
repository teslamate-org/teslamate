defmodule TeslaMateWeb.Api.Auth.AuthController do
  use TeslaMateWeb, :controller

  alias TeslaMateWeb.Api.Auth.Token

  def login(conn, %{"token" => token}) do
    config = Application.get_env(:teslamate, :api)
    auth_token = Keyword.fetch!(config, :auth_token)

    if Plug.Crypto.secure_compare(token, auth_token) do
      case Token.generate_jwt() do
        {:ok, jwt, expires_at} ->
          conn
          |> put_status(:ok)
          |> json(%{jwt: jwt, expires_at: expires_at})

        {:error, _reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to generate token"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Invalid API token"})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing 'token' parameter"})
  end
end
