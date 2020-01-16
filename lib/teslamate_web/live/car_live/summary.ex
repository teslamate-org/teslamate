defmodule TeslaMateWeb.CarLive.Summary do
  use Phoenix.LiveView

  import TeslaMateWeb.Gettext

  alias TeslaMateWeb.CarView
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.{Vehicles, Convert}

  @impl true
  def mount(%{summary: %Summary{car: car} = summary, settings: settings}, socket) do
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
      settings: settings,
      translate_state: &translate_state/1,
      duration: duration_str(summary.since),
      error: nil,
      error_timeout: nil,
      loading: false
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    CarView.render("summary.html", assigns)
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
    {:noreply, assign(socket, duration: duration_str(socket.assigns.summary.since))}
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
            error: translate_error(reason),
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
    {:noreply, assign(socket, summary: summary, duration: duration_str(since), loading: false)}
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

  defp translate_state(:start), do: nil
  defp translate_state(:driving), do: gettext("driving")
  defp translate_state(:charging), do: gettext("charging")
  defp translate_state(:updating), do: gettext("updating")
  defp translate_state(:suspended), do: gettext("falling asleep")
  defp translate_state(:online), do: gettext("online")
  defp translate_state(:offline), do: gettext("offline")
  defp translate_state(:asleep), do: gettext("asleep")
  defp translate_state(:unavailable), do: gettext("unavailable")

  defp translate_error(:unlocked), do: gettext("Car is unlocked")
  defp translate_error(:sentry_mode), do: gettext("Sentry mode is enabled")
  defp translate_error(:shift_state), do: gettext("Shift state present")
  defp translate_error(:temp_reading), do: gettext("Temperature readings")
  defp translate_error(:preconditioning), do: gettext("Preconditioning")
  defp translate_error(:user_present), do: gettext("Driver present")
  defp translate_error(:update_in_progress), do: gettext("Update in progress")
  defp translate_error(:timeout), do: gettext("Timeout")

  defp translate_error(:sleep_mode_disabled_at_location),
    do: gettext("Sleep Mode is disabled at current location")

  defp translate_error(_other), do: gettext("An error occurred")

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp duration_str(nil), do: nil

  defp duration_str(date) do
    DateTime.utc_now()
    |> DateTime.diff(date, :second)
    |> Convert.sec_to_str()
  end
end
