defmodule TeslaMateWeb.ImportLive.Index do
  use Phoenix.LiveView

  defmodule Settings do
    use Ecto.Schema
    import Ecto.Changeset

    schema("settings", do: field(:timezone, :string))

    def changeset(attrs), do: cast(%__MODULE__{}, attrs, [:timezone])
    def apply(changeset), do: apply_changes(changeset)
  end

  alias TeslaMateWeb.ImportView
  alias TeslaMate.Import

  @impl true
  def render(assigns), do: ImportView.render("index.html", assigns)

  @impl true
  def mount(_params, %{"settings" => _, "locale" => locale}, socket) do
    tz =
      if connected?(socket) do
        Gettext.put_locale(locale)
        :ok = Import.subscribe()
        get_connect_params(socket)["tz"]
      end

    timezones = Timex.timezones()
    timezone = get_timezone() || Enum.find(timezones, &match?(^tz, &1))

    socket =
      socket
      |> assign(status: Import.get_status())
      |> assign(changeset: Settings.changeset(%{timezone: timezone}))
      |> assign(timezones: timezones)

    {:ok, socket}
  end

  @impl true
  def handle_event("change", %{"settings" => attrs}, socket) do
    {:noreply, assign(socket, changeset: Settings.changeset(attrs))}
  end

  def handle_event("import", %{"settings" => attrs}, %{assigns: %{status: status}} = socket) do
    %Settings{timezone: tz} =
      attrs
      |> Settings.changeset()
      |> Settings.apply()

    :ok = Import.run(tz)

    {:noreply, assign(socket, status: %Import.Status{status | state: :running})}
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
