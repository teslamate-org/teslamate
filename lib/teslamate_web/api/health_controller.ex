defmodule TeslaMateWeb.Api.HealthController do
  use TeslaMateWeb, :controller

  def index(conn, _params) do
    db_status =
      try do
        TeslaMate.Repo.query!("SELECT 1")
        "ok"
      rescue
        _ -> "error"
      end

    status = if db_status == "ok", do: :ok, else: :service_unavailable

    conn
    |> put_status(status)
    |> json(%{
      status: db_status,
      version: to_string(Application.spec(:teslamate, :vsn))
    })
  end
end
