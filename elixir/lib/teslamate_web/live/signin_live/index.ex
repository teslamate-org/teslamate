defmodule TeslaMateWeb.SignInLive.Index do
  use TeslaMateWeb, :live_view

  import Core.Dependency, only: [call: 3]
  alias TeslaMate.{Auth, Api}

  require Logger

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, _session, socket) do
    assigns = %{
      api: get_api(socket),
      page_title: gettext("Sign in"),
      error: nil,
      signing_in: false,
      changeset: Auth.change_tokens(),
      token: System.get_env("TOKEN", ""),
      provider: System.get_env("TESLA_AUTH_HOST", "https://auth.tesla.com")
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("validate", %{"tokens" => tokens}, socket) do
    changeset =
      tokens
      |> Auth.change_tokens()
      |> Map.put(:action, :update)

    {:noreply, assign(socket, changeset: changeset, error: nil)}
  end

  # One sign-in at a time.
  def handle_event("sign_in", _, %{assigns: %{signing_in: true}} = socket), do: {:noreply, socket}

  def handle_event("sign_in", _, socket) do
    tokens = Ecto.Changeset.apply_changes(socket.assigns.changeset)
    api = socket.assigns.api

    socket =
      socket
      |> assign(signing_in: true)
      |> start_async(:sign_in, fn -> call(api, :sign_in, [tokens]) end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:sign_in, {:ok, :ok}, socket) do
    Process.sleep(250)
    {:noreply, redirect_to_carlive(socket)}
  end

  def handle_async(:sign_in, {:ok, {:error, :already_signed_in}}, socket) do
    {:noreply, redirect(socket, to: Routes.car_path(socket, :index))}
  end

  def handle_async(:sign_in, {:ok, {:error, %TeslaApi.Error{reason: :invalid_tokens}}}, socket) do
    {:noreply, assign(socket, error: gettext("Tokens are invalid"), signing_in: false)}
  end

  def handle_async(:sign_in, {:ok, {:error, %TeslaApi.Error{} = e}}, socket) do
    message = gettext("Token refresh failed: %{reason}", reason: Exception.message(e))
    {:noreply, assign(socket, error: message, signing_in: false)}
  end

  # The exit reason is internal and can span several lines, so it goes to the
  # log; the tokens in it are redacted by their schema.
  def handle_async(:sign_in, {:exit, reason}, socket) do
    Logger.error("Sign in failed: " <> Exception.format_exit(reason))
    message = gettext("Sign in failed, see the logs for details")
    {:noreply, assign(socket, error: message, signing_in: false)}
  end

  defp get_api(socket) do
    case get_connect_params(socket) do
      %{api: api} -> api
      _ -> Api
    end
  end

  defp redirect_to_carlive(socket) do
    socket
    |> put_flash(:success, gettext("Signed in successfully"))
    |> redirect(to: Routes.car_path(socket, :index))
  end
end
