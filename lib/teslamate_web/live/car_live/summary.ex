defmodule TeslaMateWeb.CarLive.Summary do
  use Phoenix.LiveView

  import TeslaMateWeb.Gettext

  alias TeslaMateWeb.CarView
  alias TeslaMate.Vehicles

  @impl true
  def mount(%{id: id, settings: settings}, socket) do
    if connected?(socket), do: Vehicles.subscribe(id)

    assigns = %{
      id: id,
      summary: Vehicles.summary(id),
      settings: settings,
      translate_state: &translate_state/1,
      error: nil,
      error_timeout: nil
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

    assigns =
      case Vehicles.suspend_logging(socket.assigns.id) do
        :ok ->
          %{error: nil, error_timeout: nil}

        {:error, reason} ->
          %{
            error: translate_error(reason),
            error_timeout: Process.send_after(self(), :hide_error, 5_000)
          }
      end

    {:noreply, assign(socket, assigns)}
  end

  def handle_event("resume_logging", _val, socket) do
    :ok = Vehicles.resume_logging(socket.assigns.id)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:hide_error, socket) do
    {:noreply, assign(socket, error: nil, error_timeout: nil)}
  end

  def handle_info(summary, socket) do
    {:noreply, assign(socket, summary: summary)}
  end

  defp translate_state(:driving), do: gettext("driving")
  defp translate_state(:charging), do: gettext("charging")
  defp translate_state(:charging_complete), do: gettext("charging complete")
  defp translate_state(:updating), do: gettext("updating")
  defp translate_state(:suspended), do: gettext("falling asleep")
  defp translate_state(:online), do: gettext("online")
  defp translate_state(:offline), do: gettext("offline")
  defp translate_state(:asleep), do: gettext("asleep")
  defp translate_state(:unavailable), do: gettext("unavailable")

  defp translate_error(:unlocked), do: gettext("Car is unlocked")
  defp translate_error(:sentry_mode), do: gettext("Sentry mode is enabled")
  defp translate_error(:preconditioning), do: gettext("Preconditioning")
  defp translate_error(:user_present), do: gettext("User present")

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)
end
