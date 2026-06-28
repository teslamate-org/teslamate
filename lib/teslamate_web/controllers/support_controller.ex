defmodule TeslaMateWeb.SupportController do
  use TeslaMateWeb, :controller

  alias TeslaMate.SupportDiagnostics

  def download(conn, _params) do
    conn
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="teslamate-support-bundle.json")
    )
    |> json(SupportDiagnostics.build())
  end
end
