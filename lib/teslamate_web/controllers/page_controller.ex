defmodule TeslaMateWeb.PageController do
  use TeslaMateWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
