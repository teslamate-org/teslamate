defmodule TeslaMateWeb.SupportController do
  use TeslaMateWeb, :controller

  alias TeslaMate.SupportDiagnostics

  def download(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="teslamate-support-bundle.json")
    )
    |> json(SupportDiagnostics.build())
  end
end
