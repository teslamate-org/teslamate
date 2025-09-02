defmodule TeslaMate.WebAuth do
  @moduledoc """
  Web访问认证模块，用于保护TeslaMate Web界面
  """

  require Logger

  @doc """
  验证Web访问密码
  """
  def verify_password(password) when is_binary(password) do
    expected_password = get_web_password()

    case expected_password do
      nil ->
        # 如果没有设置密码，允许访问
        {:ok, :no_password_set}

      expected when is_binary(expected) ->
        if password == expected do
          {:ok, :authenticated}
        else
          {:error, :invalid_password}
        end
    end
  end

  def verify_password(_), do: {:error, :invalid_password}

  @doc """
  检查是否已设置Web访问密码
  """
  def password_required? do
    case get_web_password() do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  @doc """
  检查用户是否已通过Web认证
  """
  def authenticated?(conn) do
    case Plug.Conn.get_session(conn, :web_authenticated) do
      true -> true
      _ -> false
    end
  end

  @doc """
  设置用户为已认证状态
  """
  def authenticate(conn) do
    Plug.Conn.put_session(conn, :web_authenticated, true)
  end

  @doc """
  清除用户认证状态
  """
  def deauthenticate(conn) do
    Plug.Conn.delete_session(conn, :web_authenticated)
  end

  defp get_web_password do
    System.get_env("WEB_PASSWORD")
  end
end
