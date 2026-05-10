defmodule TeslaMateWeb.DriveLive.Index do
  use TeslaMateWeb, :live_view

  import Phoenix.Component
  import Phoenix.LiveView.JS
  import TeslaMateWeb.CoreComponents

  alias TeslaMate.Log
  alias TeslaMate.Log.{Drive, Tag}
  alias TeslaMate.Repo

  import Timex, only: [format!: 2]

  @impl true
  def mount(_params, _session, socket) do
    drives = Log.list_all_drives()
    tags = Log.list_tags()

    # Add usage count to each tag
    tags_with_usage = Enum.map(tags, fn tag ->
      Map.put(tag, :usage_count, Log.count_tag_usage(tag))
    end)

    {:ok,
     socket
     |> assign(:drives, drives)
     |> assign(:tags, tags_with_usage)
     |> assign(:filtered_tags, %{})
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


  @impl true
  def handle_event("remove_tag", %{"drive_id" => drive_id, "tag_id" => tag_id}, socket) do
    try do
      drive_id_int = String.to_integer(drive_id)
      tag_id_int = String.to_integer(tag_id)

      # Check if drive exists first
      case Log.get_drive(drive_id_int) do
        nil ->
          {:noreply, put_flash(socket, :error, "Drive not found")}

        drive ->
          drive = Repo.preload(drive, :tags)

          case Log.get_tag(tag_id_int) do
            nil ->
              {:noreply, put_flash(socket, :error, "Tag not found")}

            tag ->
              case Log.remove_tag_from_drive(drive, tag) do
                {:ok, _result} ->
                  drives = Log.list_all_drives()
                  {:noreply, assign(socket, :drives, drives)}

                {:error, _error} ->
                  {:noreply, put_flash(socket, :error, "Failed to remove tag")}
              end
          end
      end
    rescue
      error ->
        {:noreply, put_flash(socket, :error, "Failed to remove tag: #{Exception.message(error)}")}
    end
  end

  @impl true
  def handle_event("add_tag_to_drive", %{"drive_id" => drive_id, "value" => tag_id}, socket) do
    if tag_id != "" do
      drive_id_int = String.to_integer(drive_id)
      tag_id_int = String.to_integer(tag_id)

      case Log.get_drive(drive_id_int) do
        nil ->
          {:noreply, put_flash(socket, :error, "Drive not found")}

        drive ->
          drive = Repo.preload(drive, :tags)

          case Log.get_tag(tag_id_int) do
            nil ->
              {:noreply, put_flash(socket, :error, "Tag not found")}

            tag ->
              case Log.add_tag_to_drive(drive, tag) do
                {:ok, _} ->
                  drives = Log.list_all_drives()
                  {:noreply, assign(socket, :drives, drives)}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "Failed to add tag")}
              end
          end
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_tag_input", %{"key" => "Enter", "value" => tag_name, "drive_id" => drive_id}, socket) do
    if String.trim(tag_name) != "" do
      drive_id_int = String.to_integer(drive_id)

      case Log.get_drive(drive_id_int) do
        nil ->
          {:noreply, put_flash(socket, :error, "Drive not found")}

        drive ->
          drive = Repo.preload(drive, :tags)
          color = "#3B82F6" # Default blue color

          # Create the tag
          case Log.create_tag(%{"name" => String.trim(tag_name), "color" => color}) do
            {:ok, tag} ->
              # Add it to the drive
              case Log.add_tag_to_drive(drive, tag) do
                {:ok, _} ->
                  drives = Log.list_all_drives()
                  tags = Log.list_tags()
                  {:noreply,
                   socket
                   |> assign(:drives, drives)
                   |> assign(:tags, tags)
                   |> push_event("clear_input", %{drive_id: drive_id})}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "Failed to add tag")}
              end

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to create tag")}
          end
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_tag_input", _params, socket) do
    # Handle other key events (ignore)
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_tags", %{"value" => query, "drive_id" => drive_id}, socket) do
    drive = Enum.find(socket.assigns.drives, &(&1.id == String.to_integer(drive_id)))
    existing_tag_ids = Enum.map(drive.tags, & &1.id)

    filtered_tags = if String.trim(query) == "" do
      Enum.filter(socket.assigns.tags, &(&1.id not in existing_tag_ids))
    else
      socket.assigns.tags
      |> Enum.filter(&(&1.id not in existing_tag_ids))
      |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(query)))
    end

    {:noreply,
     socket
     |> assign(:filtered_tags, Map.put(socket.assigns.filtered_tags, drive_id, filtered_tags))
     |> push_event("show_dropdown", %{drive_id: drive_id, show: length(filtered_tags) > 0})}
  end

  @impl true
  def handle_event("delete_tag", %{"tag_id" => tag_id}, socket) do
    tag_id_int = String.to_integer(tag_id)

    case Log.get_tag(tag_id_int) do
      nil ->
        {:noreply, put_flash(socket, :error, "Tag not found")}

      tag ->
        usage_count = Log.count_tag_usage(tag)
        drives_text = if usage_count == 1, do: "drive", else: "drives"

        {:noreply,
         push_event(socket, "confirm_delete_tag", %{
           tag_id: tag.id,
           tag_name: tag.name,
           usage_count: usage_count,
           drives_text: drives_text
         })}
    end
  end

  @impl true
  def handle_event("confirm_delete_tag", %{"tag_id" => tag_id}, socket) do
    tag_id_int = String.to_integer(tag_id)

    case Log.get_tag(tag_id_int) do
      nil ->
        {:noreply, put_flash(socket, :error, "Tag not found")}

      tag ->
        case Log.delete_tag(tag) do
          {:ok, _} ->
            # Refresh tags with updated usage counts
            refreshed_tags = Enum.map(Log.list_tags(), fn t ->
              Map.put(t, :usage_count, Log.count_tag_usage(t))
            end)

            {:noreply,
             socket
             |> assign(:tags, refreshed_tags)
             |> assign(:drives, Log.list_all_drives())
             |> put_flash(:info, "Tag '#{tag.name}' has been deleted successfully")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to delete tag: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("add_existing_tag", %{"drive_id" => drive_id, "tag_id" => tag_id}, socket) do
    drive_id_int = String.to_integer(drive_id)
    tag_id_int = String.to_integer(tag_id)

    case Log.get_drive(drive_id_int) do
      nil ->
        {:noreply, put_flash(socket, :error, "Drive not found")}

      drive ->
        drive = Repo.preload(drive, :tags)

        case Log.get_tag(tag_id_int) do
          nil ->
            {:noreply, put_flash(socket, :error, "Tag not found")}

          tag ->
            case Log.add_tag_to_drive(drive, tag) do
              {:ok, _} ->
                drives = Log.list_all_drives()
                {:noreply,
                 socket
                 |> assign(:drives, drives)
                 |> push_event("clear_input", %{drive_id: drive_id})
                 |> push_event("hide_dropdown", %{drive_id: drive_id})}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to add tag")}
            end
        end
    end
  end

  @impl true
  def handle_event("save_notes", %{"value" => notes, "drive_id" => drive_id}, socket) do
    drive_id_int = String.to_integer(drive_id)

    case Log.get_drive(drive_id_int) do
      nil ->
        {:noreply, put_flash(socket, :error, "Drive not found")}

      drive ->
        case Log.update_drive(drive, %{notes: String.trim(notes)}) do
          {:ok, _} ->
            drives = Log.list_all_drives()
            {:noreply, assign(socket, :drives, drives)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to save notes")}
        end
    end
  end


  # Helper functions
  def format_drive_date(datetime) do
    # Convert UTC datetime to PST/PDT
    pst_datetime = datetime
    |> Timex.to_datetime("America/Los_Angeles")

    format!(pst_datetime, "{WDfull}, {YYYY}-{0M}-{0D} {h24}:{m}")
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
