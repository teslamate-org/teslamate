defmodule TeslaMateWeb.DonateController do
  use TeslaMateWeb, :controller

  action_fallback TeslaMateWeb.FallbackController

  @url "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=YE4CPXRAV9CVL&source=url"
  @max_age 1 * 24 * 60 * 60

  def index(conn, _opts) do
    value = to_string(times_clicked(conn) + 1)

    conn
    |> put_resp_cookie("donate", value, max_age: @max_age)
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
