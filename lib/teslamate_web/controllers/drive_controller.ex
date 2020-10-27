defmodule TeslaMateWeb.DriveController do
  use TeslaMateWeb, :controller

  require Logger

  alias TeslaMate.Log.Drive
  alias TeslaMate.Repo

  def gpx(conn, %{"id" => id}) do
    drive = Repo.get(Drive, id) |> Repo.preload(:positions)

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
