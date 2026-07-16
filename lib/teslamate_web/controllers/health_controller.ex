defmodule TeslaMateWeb.HealthController do
  use TeslaMateWeb, :controller

  alias TeslaMate.{Repo, RuntimeHealth}

  def index(conn, _params) do
    case Repo.query("SELECT 1", []) do
      {:ok, _result} ->
        case RuntimeHealth.public_report() do
          {:ok, report} ->
            conn
            |> put_resp_header("cache-control", "no-store")
            |> json(report)

          {:error, :unavailable} ->
            unavailable(conn, :runtime_health_unavailable)
        end

      {:error, _reason} ->
        unavailable(conn, :database_unavailable)
    end
  end

  defp unavailable(conn, reason) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:service_unavailable)
    |> json(%{schema_version: 1, status: :unavailable, reason: reason})
  end
end
