defmodule TeslaMateWeb.ApiCase do
  @moduledoc """
  Test case for API endpoint tests.

  Provides JWT authentication helpers and JSON setup.
  """

  use ExUnit.CaseTemplate

  alias TeslaMateWeb.Api.Auth.Token

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import TeslaMateWeb.ApiCase

      @endpoint TeslaMateWeb.Endpoint

      use TeslaMateWeb, :verified_routes
    end
  end

  setup tags do
    try do
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TeslaMate.Repo, shared: not tags[:async])
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    rescue
      e in [MatchError] ->
        case e.term do
          {:error, {{:badmatch, :already_shared}, _}} -> :ok
          _ -> reraise e, __STACKTRACE__
        end
    end

    {:ok, _pid} = start_supervised(TeslaMateWeb.Endpoint)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "application/json")

    {:ok, conn: conn}
  end

  @doc "Add a valid JWT Bearer token to the connection"
  def authenticate(conn) do
    {:ok, jwt, _exp} = Token.generate_jwt()
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{jwt}")
  end

  @doc "Create a test car in the database"
  def create_test_car(attrs \\ %{}) do
    defaults = %{
      eid: 1001,
      vid: 2001,
      vin: "TEST00000000VIN01",
      name: "Test Car",
      model: "S",
      efficiency: 0.153
    }

    {:ok, car} = TeslaMate.Log.create_car(Map.merge(defaults, attrs))
    car
  end
end
