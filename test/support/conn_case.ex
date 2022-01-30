defmodule TeslaMateWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TeslaMateWeb.ConnCase

      alias TeslaMateWeb.Router.Helpers, as: Routes
      import Phoenix.LiveViewTest

      # The default endpoint for testing
      @endpoint TeslaMateWeb.Endpoint
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

    # Start the Endpoint manually since tests run with '--no-start'
    {:ok, _pid} = start_supervised(TeslaMateWeb.Endpoint)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.assign(:signed_in?, !!tags[:signed_in])

    {:ok, conn: conn}
  end
end
