defmodule TeslaMateWeb.SignInLive.Index do
  use TeslaMateWeb, :live_view

  import Core.Dependency, only: [call: 3]
  alias TeslaMate.{Auth, Api}

  @impl true
  def mount(_params, %{"locale" => locale}, socket) do
    if connected?(socket), do: Gettext.put_locale(locale)

    assigns = %{
      changeset: Auth.change_credentials(),
      error: nil,
      api: get_api(socket),
      page_title: gettext("Sign in")
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("validate", %{"credentials" => credentials}, socket) do
    changeset =
      credentials
      |> Auth.change_credentials()
      |> Map.put(:action, :update)

    {:noreply, assign(socket, changeset: changeset, error: nil)}
  end

  def handle_event("save", _params, socket) do
    credentials = Ecto.Changeset.apply_changes(socket.assigns.changeset)

    case call(socket.assigns.api, :sign_in, [credentials]) do
      {:error, reason} ->
        {:noreply, assign(socket, error: reason)}

      :ok ->
        Process.sleep(250)
        {:noreply, redirect_to_carlive(socket)}
    end
  end

  ## Private

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
