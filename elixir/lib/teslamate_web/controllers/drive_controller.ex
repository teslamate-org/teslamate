defmodule TeslaMateWeb.DriveController do
  use TeslaMateWeb, :controller

  require Logger
  import Ecto.Query

  alias TeslaMate.Log.{Drive, Position}
  alias TeslaMate.Repo

  def gpx(conn, %{"id" => id}) do
    drive =
      Drive
      |> Repo.get(id)
      |> Repo.preload(positions: from(p in Position, order_by: p.date))

    case drive do
      nil -> conn |> send_resp(404, "Drive not found")
      drive -> send_gpx_file(conn, drive)
    end
  end

  defp send_gpx_file(conn, drive) do
    filename = "#{drive.start_date}.gpx"

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> render("gpx.xml", drive: drive)
  end
end
