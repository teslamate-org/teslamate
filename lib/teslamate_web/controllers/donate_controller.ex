defmodule TeslaMateWeb.DonateController do
  use TeslaMateWeb, :controller

  alias TeslaMateWeb.Plugs.Donate

  action_fallback TeslaMateWeb.FallbackController

  @url "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=YE4CPXRAV9CVL&source=url"

  def index(conn, _opts) do
    value = to_string(times_clicked(conn) + 1)

    conn
    |> put_resp_cookie("donate", value, max_age: Donate.max_age())
    |> redirect(external: @url)
    |> halt()
  end

  defp times_clicked(conn) do
    with %{cookies: %{"donate" => n}} <- conn,
         {n, ""} <- Integer.parse(n) do
      n
    else
      _ -> 0
    end
  end
end
