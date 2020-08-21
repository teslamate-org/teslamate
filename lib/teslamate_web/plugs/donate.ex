defmodule TeslaMateWeb.Plugs.Donate do
  import Plug.Conn

  alias TeslaMate.{Release, Import}

  @max_age 30 * 24 * 60 * 60
  def max_age, do: @max_age

  def init(opts), do: opts

  def call(%{req_cookies: %{"donate" => n}} = conn, _opts) when is_binary(n), do: conn
  def call(conn, _opts), do: put_donate_cookie(conn)

  defp put_donate_cookie(conn) do
    if importing_data?() or Release.seconds_since_last_migration() < @max_age / 2 do
      put_resp_cookie(conn, "donate", "0", max_age: @max_age, same_site: "Strict")
    else
      conn
    end
  end

  defp importing_data? do
    with pid when is_pid(pid) <- Process.whereis(Import),
         true <- Process.alive?(pid),
         %Import.Status{state: s} when s != :error <- Import.get_status() do
      true
    else
      _ -> false
    end
  end
end
