defmodule TeslaMateWeb.Api.UserSocket do
  use Phoenix.Socket

  alias TeslaMateWeb.Api.Auth.Token

  channel "vehicle:*", TeslaMateWeb.Api.VehicleChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Token.verify_jwt(token) do
      {:ok, claims} ->
        {:ok, assign(socket, :current_user, claims["sub"])}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
