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
      use Phoenix.ConnTest
      alias TeslaMateWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint TeslaMateWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TeslaMate.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TeslaMate.Repo, {:shared, self()})
    end

    # Start the Endpoint manually since tests run with '--no-start'
    {:ok, _pid} = start_supervised(TeslaMateWeb.Endpoint)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
