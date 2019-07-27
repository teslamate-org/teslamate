defmodule TeslaMateWeb.LiveViewSocket do
  @moduledoc """
  The LiveView socket for Phoenix Endpoints.

  Switch to Phoenix.LiveView.Socket if log opts are accepted.

  https://github.com/phoenixframework/phoenix_live_view/blob/master/lib/phoenix_live_view/socket.ex
  """
  use Phoenix.Socket, log: :debug

  defstruct id: nil,
            endpoint: nil,
            view: nil,
            router: nil,
            parent_pid: nil,
            assigns: %{},
            changed: %{},
            fingerprints: {nil, %{}},
            private: %{},
            redirected: nil,
            connected?: false

  channel "lv:*", Phoenix.LiveView.Channel

  @doc """
  Connects the Phoenix.Socket for a LiveView client.
  """
  @impl Phoenix.Socket
  def connect(_params, %Phoenix.Socket{} = socket, _connect_info) do
    {:ok, socket}
  end

  @doc """
  Identifies the Phoenix.Socket for a LiveView client.
  """
  @impl Phoenix.Socket
  def id(_socket), do: nil
end
