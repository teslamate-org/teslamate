defmodule TeslaMateWeb.ImportLive.Index do
  use TeslaMateWeb, :live_view

  defmodule Settings do
    use Ecto.Schema
    import Ecto.Changeset

    schema("settings", do: field(:timezone, :string))

    def changeset(attrs), do: cast(%__MODULE__{}, attrs, [:timezone])
    def apply(changeset), do: apply_changes(changeset)
  end

  alias TeslaMate.Import
  alias TeslaMate.Import.RejectedRow

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"settings" => _}, socket) do
    tz =
      if connected?(socket) do
        :ok = Import.subscribe()
        get_connect_params(socket)["tz"]
      end

    if Import.enabled?() do
      timezones = Timex.timezones()
      status = Import.get_status()

      timezone =
        status.resume_timezone || get_timezone() || Enum.find(timezones, &match?(^tz, &1))

      socket =
        socket
        |> assign(status: status)
        |> assign(changeset: Settings.changeset(%{timezone: timezone}))
        |> assign(timezones: timezones, page_title: gettext("Import"))

      {:ok, socket}
    else
      {:ok, redirect(socket, to: Routes.car_path(socket, :index))}
    end
  end

  @impl true
  def handle_event("change", %{"settings" => attrs}, socket) do
    {:noreply, assign(socket, changeset: Settings.changeset(attrs))}
  end

  def handle_event(
        "import",
        %{"settings" => attrs},
        %{assigns: %{status: %Import.Status{} = status}} = socket
      ) do
    %Settings{timezone: tz} =
      attrs
      |> Settings.changeset()
      |> Settings.apply()

    case Import.run(tz) do
      :ok ->
        {:noreply, assign(socket, status: %{status | state: :running})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, import_start_error(reason))}
    end
  end

  def handle_event("discard-interrupted-import", _params, socket) do
    case Import.discard_interrupted_run() do
      :ok ->
        socket =
          socket
          |> assign(status: Import.get_status())
          |> put_flash(:info, gettext("Interrupted import discarded."))

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("The import can no longer be discarded."))}
    end
  end

  def handle_event("reload", _params, socket) do
    :ok = Import.reload_directory()
    {:noreply, socket}
  end

  @impl true
  def handle_info(%Import.Status{} = status, socket) do
    {:noreply, assign(socket, status: status)}
  end

  ## Private

  defp rejection_reason(%RejectedRow{reason: :invalid_fields, fields: fields}) do
    gettext("invalid values for %{fields}", fields: Enum.join(fields, ", "))
  end

  defp rejection_reason(%RejectedRow{reason: :invalid_date}) do
    gettext("invalid date")
  end

  defp rejection_reason(%RejectedRow{reason: :ambiguous_local_time}) do
    gettext("ambiguous local time")
  end

  defp rejection_reason(%RejectedRow{reason: :nonexistent_local_time}) do
    gettext("nonexistent local time")
  end

  defp rejection_reason(%RejectedRow{reason: :invalid_timezone}) do
    gettext("date could not be converted in the selected time zone")
  end

  defp rejection_reason(%RejectedRow{reason: :column_count_mismatch}) do
    gettext("column count does not match the header")
  end

  defp rejection_reason(%RejectedRow{}) do
    gettext("row could not be parsed")
  end

  defp import_error(:vehicle_data_incomplete) do
    gettext("No complete vehicle data was found in the import files.")
  end

  defp import_error(:vehicle_changed) do
    gettext("The import files contain data for more than one vehicle.")
  end

  defp import_error(message), do: inspect(message, pretty: true)

  defp import_start_error(:no_files), do: gettext("No import files were found.")

  defp import_start_error(:not_allowed) do
    gettext("The import is no longer idle. Reload and try again.")
  end

  defp import_start_error(_reason), do: gettext("The import could not be started.")

  defp get_timezone do
    case Timex.local() do
      %DateTime{time_zone: tz} -> tz
      _ -> nil
    end
  rescue
    _ ->
      # https://github.com/bitwalker/timex/issues/521
      nil
  end
end
