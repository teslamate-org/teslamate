defmodule TeslaMateWeb.DriveLive.FormComponent do
  use TeslaMateWeb, :live_component

  import Phoenix.Component
  import TeslaMateWeb.CoreComponents

  alias TeslaMate.Log

  @impl true
  def update(%{drive: drive} = assigns, socket) do
    changeset = TeslaMate.Log.Drive.changeset(drive, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"drive" => drive_params}, socket) do
    changeset =
      socket.assigns.drive
      |> TeslaMate.Log.Drive.changeset(drive_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"drive" => drive_params}, socket) do
    save_drive(socket, socket.assigns.action, drive_params)
  end

  def handle_event("add_tag", %{"tag_id" => tag_id}, socket) do
    drive = socket.assigns.drive
    tag = Log.get_tag!(tag_id)

    case Log.add_tag_to_drive(drive, tag) do
      {:ok, _} ->
        drive = Log.get_drive!(drive.id) |> TeslaMate.Repo.preload(:tags)
        {:noreply, assign(socket, drive: drive)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add tag")}
    end
  end

  def handle_event("remove_tag", %{"tag_id" => tag_id}, socket) do
    drive = socket.assigns.drive
    tag = Log.get_tag!(tag_id)

    case Log.remove_tag_from_drive(drive, tag) do
      {:ok, _} ->
        drive = Log.get_drive!(drive.id) |> TeslaMate.Repo.preload(:tags)
        {:noreply, assign(socket, drive: drive)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove tag")}
    end
  end

  def handle_event("create_tag", %{"tag" => tag_params}, socket) do
    case Log.create_tag(tag_params) do
      {:ok, _tag} ->
        tags = Log.list_tags()
        {:noreply,
         socket
         |> assign(:tags, tags)
         |> put_flash(:info, "Tag created successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, tag_changeset: changeset)}
    end
  end

  defp save_drive(socket, :edit, drive_params) do
    case Log.update_drive(socket.assigns.drive, drive_params) do
      {:ok, _drive} ->
        {:noreply,
         socket
         |> put_flash(:info, "Drive updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_drive(socket, :new, drive_params) do
    case Log.create_drive(drive_params) do
      {:ok, _drive} ->
        {:noreply,
         socket
         |> put_flash(:info, "Drive created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
