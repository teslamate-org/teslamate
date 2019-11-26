defmodule TeslaMateWeb.LiveViewSocket do
  @moduledoc """
  The LiveView socket for Phoenix Endpoints.

  Switch to Phoenix.LiveView.Socket if log opts are accepted.

  https://github.com/phoenixframework/phoenix_live_view/blob/master/lib/phoenix_live_view/socket.ex
  """
  use Phoenix.Socket, log: :debug

  if Version.match?(System.version(), ">= 1.8.0") do
    @derive {Inspect, only: [:id, :endpoint, :view, :parent_pid, :root_id, :assigns, :changed]}
  end

  defstruct id: nil,
            endpoint: nil,
            view: nil,
            parent_pid: nil,
            root_pid: nil,
            assigns: %{},
            changed: %{},
            private: %{},
            fingerprints: Phoenix.LiveView.Diff.new_fingerprints(),
            redirected: nil,
            connected?: false

  @type t :: %__MODULE__{}
  @type unsigned_params :: map
  @type assigns :: map

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
