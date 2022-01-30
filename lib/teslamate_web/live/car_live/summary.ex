defmodule TeslaMateWeb.CarLive.Summary do
  use TeslaMateWeb, :live_view

  import TeslaMateWeb.Gettext

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.{Vehicles, Convert}

  on_mount {TeslaMateWeb.InitAssigns, :locale}

  @impl true
  def mount(_params, %{"summary" => %Summary{car: car} = summary} = session, socket) do
    if connected?(socket) do
      send(self(), :update_duration)
      send(self(), {:status, Vehicle.busy?(car.id)})

      :ok = Vehicles.subscribe_to_summary(car.id)
      :ok = Vehicles.subscribe_to_fetch(car.id)
    end

    assigns = %{
      car: car,
      summary: summary,
      fetch_status: Vehicle.busy?(car.id),
      fetch_start: 0,
      fetch_timer: nil,
      settings: session["settings"],
      translate_state: &translate_state/1,
      duration: humanize_duration(summary.since),
      error: nil,
      error_timeout: nil,
      loading: false
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("suspend_logging", _val, socket) do
    cancel_timer(socket.assigns.error_timeout)
    send(self(), :suspend_logging)
    {:noreply, assign(socket, loading: true)}
  end

  def handle_event("resume_logging", _val, socket) do
    send(self(), :resume_logging)
    {:noreply, assign(socket, loading: true)}
  end

  @impl true
  def handle_info(:update_duration, socket) do
    Process.send_after(self(), :update_duration, :timer.seconds(1))
    {:noreply, assign(socket, duration: humanize_duration(socket.assigns.summary.since))}
  end

  def handle_info(:resume_logging, socket) do
    :ok = Vehicles.resume_logging(socket.assigns.car.id)
    {:noreply, socket}
  end

  def handle_info(:suspend_logging, socket) do
    assigns =
      case Vehicles.suspend_logging(socket.assigns.car.id) do
        :ok ->
          %{error: nil, error_timeout: nil, loading: false}

        {:error, reason} ->
          %{
            error: error_to_str(reason),
            error_timeout: Process.send_after(self(), :hide_error, 5_000),
            loading: false
          }
      end

    {:noreply, assign(socket, assigns)}
  end

  def handle_info(:hide_error, socket) do
    {:noreply, assign(socket, error: nil, error_timeout: nil)}
  end

  def handle_info(%Summary{since: since} = summary, socket) do
    {:noreply,
     assign(socket, summary: summary, duration: humanize_duration(since), loading: false)}
  end

  def handle_info({:status, true}, socket) do
    cancel_timer(socket.assigns.fetch_timer)

    assigns = %{
      fetch_status: true,
      fetch_start: System.monotonic_time(),
      fetch_timer: nil
    }

    {:noreply, assign(socket, assigns)}
  end

  # Note: this must be smaller than the @driving_interval
  @min_spinner_visibility_ms 1000

  def handle_info({:status, false}, socket) do
    fetch_duration =
      (System.monotonic_time() - socket.assigns.fetch_start) /
        System.convert_time_unit(1, :millisecond, :native)

    assigns =
      case @min_spinner_visibility_ms - fetch_duration do
        diff when 0 < diff ->
          %{fetch_timer: Process.send_after(self(), :set_status_to_false, round(diff))}

        _ ->
          %{fetch_status: false}
      end

    {:noreply, assign(socket, assigns)}
  end

  def handle_info(:set_status_to_false, socket) do
    {:noreply, assign(socket, fetch_status: false)}
  end

  defp translate_state(:start), do: ""
  defp translate_state(:driving), do: gettext("driving")
  defp translate_state(:charging), do: gettext("charging")
  defp translate_state(:updating), do: gettext("updating")
  defp translate_state(:suspended), do: gettext("falling asleep")
  defp translate_state(:online), do: gettext("online")
  defp translate_state(:offline), do: gettext("offline")
  defp translate_state(:asleep), do: gettext("asleep")
  defp translate_state(:unavailable), do: gettext("unavailable")

  defp error_to_str(:unlocked), do: gettext("Car is unlocked")
  defp error_to_str(:doors_open), do: gettext("Doors are open")
  defp error_to_str(:trunk_open), do: gettext("Trunk is open")
  defp error_to_str(:sentry_mode), do: gettext("Sentry mode is enabled")
  defp error_to_str(:preconditioning), do: gettext("Preconditioning")
  defp error_to_str(:user_present), do: gettext("Driver present")
  defp error_to_str(:downloading_update), do: gettext("Downloading update")
  defp error_to_str(:update_in_progress), do: gettext("Update in progress")
  defp error_to_str(:timeout), do: gettext("Timeout")
  defp error_to_str(_other), do: gettext("An error occurred")

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp humanize_duration(nil), do: nil

  defp humanize_duration(date) do
    case DateTime.utc_now() |> DateTime.diff(date, :second) do
      dur when dur < 5 -> nil
      dur when dur > 60 -> dur |> Convert.sec_to_str() |> Enum.reject(&String.ends_with?(&1, "s"))
      dur -> dur |> Convert.sec_to_str()
    end
  end
end
