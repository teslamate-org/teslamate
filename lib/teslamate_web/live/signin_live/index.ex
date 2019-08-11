defmodule TeslaMateWeb.SignInLive.Index do
  use Phoenix.LiveView

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.SigninView
  alias TeslaMateWeb.CarLive

  alias TeslaMate.Auth
  alias TeslaMate.Api

  import Core.Dependency, only: [call: 3]
  import TeslaMateWeb.Gettext

  @impl true
  def mount(_session, socket) do
    assigns = %{
      changeset: Auth.change_credentials(),
      error: nil,
      api: get_api(socket)
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns), do: SigninView.render("index.html", assigns)

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
        :timer.sleep(250)
        {:stop, redirect_to_carlive(socket)}
    end
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
    |> redirect(to: Routes.live_path(socket, CarLive.Index, %{}))
  end
end
