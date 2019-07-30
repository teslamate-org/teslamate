defmodule TeslaMateWeb.SignInLive.Index do
  use Phoenix.LiveView

  alias TeslaMateWeb.Router.Helpers, as: Routes
  alias TeslaMateWeb.SigninView
  alias TeslaMateWeb.CarLive

  alias TeslaMate.Auth
  alias TeslaMate.Api

  @impl true
  def mount(_session, socket) do
    {:ok, assign(socket, %{changeset: Auth.change_credentials(), error: nil})}
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

    case Api.sign_in(credentials) do
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
      :ok -> {:stop, redirect_to_carlive(socket)}
    end
  end

  defp redirect_to_carlive(socket) do
    socket
    |> put_flash(:success, "Signed in successfully.")
    |> redirect(to: Routes.live_path(socket, CarLive.Index, %{}))
  end
end
