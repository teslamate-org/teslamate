defmodule TeslaMateWeb.MaintenanceLive.Index do
  use TeslaMateWeb, :live_view

  alias TeslaMate.DataHealth

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_report(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_report(socket)}
  end

  defp load_report(socket) do
    assign(socket,
      page_title: gettext("Maintenance"),
      report: DataHealth.report()
    )
  end

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

  defp open_hours(%{open_after_seconds: seconds}), do: div(seconds, 60 * 60)
end
