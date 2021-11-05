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
      timezone = get_timezone() || Enum.find(timezones, &match?(^tz, &1))

      socket =
        socket
        |> assign(status: Import.get_status())
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
