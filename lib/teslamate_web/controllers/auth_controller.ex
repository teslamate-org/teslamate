defmodule TeslaMateWeb.AuthController do
  use TeslaMateWeb, :controller

  alias TeslaMate.WebAuth

  def authenticate(conn, %{"password" => password}) do
    case WebAuth.verify_password(password) do
      {:ok, :authenticated} ->
        conn
        |> WebAuth.authenticate()
        |> put_flash(:info, "认证成功")
        |> redirect(to: "/")

      {:ok, :no_password_set} ->
        redirect(conn, to: "/")

      {:error, :invalid_password} ->
        conn
        |> put_flash(:error, "密码错误，请重试")
        |> redirect(to: "/web_auth")
    end
  end

  def logout(conn, _params) do
    conn
    |> WebAuth.deauthenticate()
    |> put_flash(:info, "已退出登录")
    |> redirect(to: "/web_auth")
  end
end