defmodule TeslaMateWeb.DriveController do
  use TeslaMateWeb, :controller

  require Logger

  alias TeslaMate.Log.Drive
  alias TeslaMate.Repo

  def index(conn, %{"id" => id}) do
    drive = Repo.get(Drive, id) |> Repo.preload(:positions)
    filename = drive.start_date

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}.gpx"))
    |> render("gpx.xml", drive: drive)
  end
end

defmodule TeslaMateWeb.DriveView do
  use TeslaMateWeb, :view
end
