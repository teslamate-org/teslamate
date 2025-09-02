defmodule TeslaMateWeb.WebAuthLive.Index do
  use TeslaMateWeb, :live_view

  alias TeslaMate.WebAuth

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, _session, socket) do
    # 如果不需要密码，直接重定向到首页
    if not WebAuth.password_required?() do
      {:ok, redirect(socket, to: "/")}
    else
      assigns = %{
        page_title: gettext("Web Access Authentication"),
        error: nil,
        password: ""
      }

      {:ok, assign(socket, assigns)}
    end
  end

  @impl true
  def handle_event("validate", %{"password" => password}, socket) do
    {:noreply, assign(socket, password: password, error: nil)}
  end

  # 认证已改为通过表单提交到控制器处理
  # LiveView只处理前端验证

end
