defmodule TeslaMateWeb.DriveLive.Index do
  use TeslaMateWeb, :live_view

  import Phoenix.Component
  import TeslaMateWeb.CoreComponents

  alias TeslaMate.Log
  alias TeslaMate.Log.{Drive, Tag}

  import Timex, only: [format!: 2]

  @impl true
  def mount(_params, _session, socket) do
    drives = Log.list_drives()
    tags = Log.list_tags()

    {:ok,
     socket
     |> assign(:drives, drives)
     |> assign(:tags, tags)
     |> assign(:page_title, "Drives")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Drives")
    |> assign(:drive, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    drive = Log.get_drive!(id) |> TeslaMate.Repo.preload(:tags)

    socket
    |> assign(:page_title, "Edit Drive")
    |> assign(:drive, drive)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    drive = Log.get_drive!(id)
    {:ok, _} = Log.delete_drive(drive)

    {:noreply, assign(socket, :drives, Log.list_drives())}
  end

  @impl true
  def handle_event("update_drive", %{"drive" => drive_params}, socket) do
    drive = socket.assigns.drive

    case Log.update_drive(drive, drive_params) do
      {:ok, _drive} ->
        {:noreply,
         socket
         |> put_flash(:info, "Drive updated successfully")
         |> push_patch(to: ~p"/drives")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
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

  @impl true
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

  @impl true
  def handle_event("create_tag", %{"tag" => tag_params}, socket) do
    case Log.create_tag(tag_params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> assign(:tags, Log.list_tags())
         |> put_flash(:info, "Tag created successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, tag_changeset: changeset)}
    end
  end

  # Helper functions
  def format_drive_date(datetime) do
    format!(datetime, "{YYYY}-{0M}-{0D} {h24}:{m}")
  end

  def format_distance(distance) when is_number(distance) do
    :erlang.float_to_binary(distance, decimals: 1)
  end

  def format_distance(_), do: "0.0"

  def format_duration(minutes) when is_number(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 and mins > 0 -> "#{hours}h #{mins}m"
      hours > 0 -> "#{hours}h"
      true -> "#{mins}m"
    end
  end

  def format_duration(_), do: "0m"
end
