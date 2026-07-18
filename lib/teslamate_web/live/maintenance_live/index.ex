defmodule TeslaMateWeb.MaintenanceLive.Index do
  use TeslaMateWeb, :live_view

  alias TeslaMate.{BuildInfo, DataHealth, FileLog, Maintenance, RuntimeHealth}

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_report(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> clear_flash() |> load_report()}
  end

  def handle_event("request-close", %{"finding-id" => finding_id}, socket) do
    case Enum.find(socket.assigns.report.findings, &(&1.id == finding_id)) do
      nil ->
        {:noreply,
         socket
         |> clear_flash()
         |> put_flash(
           :error,
           gettext("This session is no longer listed. Refresh and try again.")
         )}

      finding ->
        {:noreply, socket |> clear_flash() |> assign(pending_action: finding)}
    end
  end

  def handle_event("cancel-close", _params, socket) do
    {:noreply, assign(socket, pending_action: nil)}
  end

  def handle_event("confirm-close", _params, %{assigns: %{pending_action: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("confirm-close", _params, socket) do
    finding = socket.assigns.pending_action

    case Maintenance.close(finding.entity_type, finding.entity_id) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> clear_flash()
         |> put_flash(:info, gettext("Session closed."))
         |> load_report()}

      {:error, reason} ->
        {:noreply,
         socket
         |> clear_flash()
         |> put_flash(:error, action_error(reason))
         |> load_report()}
    end
  end

  defp load_report(socket) do
    file_log_status = FileLog.status()

    assign(socket,
      page_title: gettext("Maintenance"),
      report: DataHealth.report(),
      build_info: BuildInfo.current(),
      runtime_health: runtime_health(),
      file_log_status: file_log_status,
      log_tail: log_tail(file_log_status),
      maintenance_actions_enabled?: Maintenance.enabled?(),
      pending_action: nil
    )
  end

  defp runtime_health do
    case RuntimeHealth.report() do
      %{status: _status, mqtt: %{status: _mqtt_status}, vehicles: vehicles} = report
      when is_list(vehicles) ->
        report

      _other ->
        %{status: :unavailable, mqtt: %{status: :unavailable}, vehicles: []}
    end
  end

  defp log_tail(%{enabled?: true}), do: FileLog.tail()
  defp log_tail(_status), do: {:error, :disabled}

  defp finding_title(%{entity_type: :drive, entity_id: id}) do
    gettext("Drive #%{id}", id: id)
  end

  defp finding_title(%{entity_type: :charging_process, entity_id: id}) do
    gettext("Charging session #%{id}", id: id)
  end

  defp finding_icon(%{entity_type: :drive}), do: "mdi-road-variant"
  defp finding_icon(%{entity_type: :charging_process}), do: "mdi-ev-station"

  defp car_name(%{car_name: name}) when is_binary(name) and name != "", do: name
  defp car_name(%{car_id: id}), do: gettext("Car %{id}", id: id)

  defp finding_dom_id(%{entity_type: type, entity_id: id}), do: "finding-#{type}-#{id}"

  defp iso_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso_datetime(datetime) when is_binary(datetime), do: datetime

  defp open_hours(%{open_after_seconds: seconds}), do: div(seconds, 60 * 60)

  defp status_label(:ok), do: gettext("Healthy")
  defp status_label(:idle), do: gettext("Idle")
  defp status_label(:degraded), do: gettext("Degraded")
  defp status_label(:down), do: gettext("Down")
  defp status_label(:disabled), do: gettext("Disabled")
  defp status_label(:unknown), do: gettext("Unknown")
  defp status_label(:unavailable), do: gettext("Unavailable")
  defp status_label(_status), do: gettext("Unknown")

  defp status_class(:ok), do: "is-success"
  defp status_class(:idle), do: "is-info is-light"
  defp status_class(:degraded), do: "is-warning"
  defp status_class(:down), do: "is-danger"
  defp status_class(:disabled), do: "is-light"
  defp status_class(_status), do: "is-light"

  defp component_reason(%{reason: nil}), do: nil
  defp component_reason(%{reason: reason}), do: format_atom(reason)
  defp component_reason(_component), do: nil

  defp format_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_atom(value), do: to_string(value)

  defp format_bytes(nil), do: gettext("Unknown")
  defp format_bytes(bytes) when bytes < 1_000, do: gettext("%{bytes} B", bytes: bytes)

  defp format_bytes(bytes) when bytes < 1_000_000 do
    gettext("%{kilobytes} KB", kilobytes: Float.round(bytes / 1_000, 1))
  end

  defp format_bytes(bytes) do
    gettext("%{megabytes} MB", megabytes: Float.round(bytes / 1_000_000, 1))
  end

  defp flash_class(:error), do: "is-danger"
  defp flash_class(:info), do: "is-success"
  defp flash_class(_key), do: "is-info"

  defp action_error(:disabled), do: gettext("Maintenance actions are disabled.")

  defp action_error(:not_eligible),
    do: gettext("The session changed and is no longer eligible. Nothing was changed.")

  defp action_error(:vehicle_active),
    do: gettext("The vehicle is currently active. Nothing was changed.")

  defp action_error(:insufficient_data),
    do:
      gettext(
        "The drive does not have enough position data to close safely. Nothing was changed."
      )

  defp action_error(_reason),
    do: gettext("The session could not be closed. Nothing was changed.")
end
