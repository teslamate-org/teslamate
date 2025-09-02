defmodule TeslaMateWeb.Plugs.WebAuth do
  @moduledoc """
  Web访问认证中间件
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  alias TeslaMate.WebAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    # 如果不需要密码或已经认证，直接通过
    if not WebAuth.password_required?() or WebAuth.authenticated?(conn) do
      conn
    else
      # 重定向到密码输入页面
      conn
      |> put_flash(:error, "需要输入密码才能访问")
      |> redirect(to: "/web_auth")
      |> halt()
    end
  end
end
