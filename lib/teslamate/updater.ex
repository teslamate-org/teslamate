defmodule TeslaMate.Updater do
  use GenServer

  alias Finch.Response
  alias TeslaMate.HTTP
  require Logger

  defmodule State, do: defstruct([:update, :version])
  defmodule Release, do: defstruct([:version, :prerelease])

  @url "https://api.github.com/repos/adriankumpf/teslamate/releases/latest"
  @name __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def get_update(name \\ @name) do
    GenServer.call(name, :get_update, 50)
  catch
    :exit, {:timeout, _} -> nil
    :exit, {:noproc, _} -> nil
  end

  @impl true
  def init(opts) do
    check_after = Keyword.get(opts, :check_after, :timer.minutes(5))
    interval = Keyword.get(opts, :interval, :timer.hours(72))
    version = Keyword.get_lazy(opts, :version, &version/0)

    {:ok, _} = :timer.send_interval(interval, :check_for_updates)

    case check_after do
      0 ->
        {:ok, %State{version: version}, {:continue, :check_for_updates}}

      t when is_number(t) and 0 < t ->
        Process.send_after(self(), :check_for_updates, t)
        {:ok, %State{version: version}}
    end
  end

  @impl true
  def handle_continue(:check_for_updates, %State{version: current_vsv} = state) do
    Logger.debug("Checking for updates …")

    case fetch_release() do
      {:ok, %Release{version: version, prerelease: false}} ->
        case Version.compare(current_vsv, version) do
          :lt ->
            Logger.info("Update available: #{current_vsv} -> #{version}")
            {:noreply, %State{state | update: version}}

          _ ->
            Logger.debug("No update availble")
            {:noreply, state}
        end

      {:ok, %Release{version: version, prerelease: true}} ->
        Logger.debug("Prerelease availble: #{version}")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Update check failed: #{inspect(reason, pretty: true)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:check_for_updates, state) do
    {:noreply, state, {:continue, :check_for_updates}}
  end

  @impl true
  def handle_call(:get_update, _from, %State{update: update} = state) do
    {:reply, update, state}
  end

  ## Private

  defp version, do: "#{Application.spec(:teslamate, :vsn)}"

  defp fetch_release do
    case HTTP.get(@url, receive_timeout: 30_000) do
      {:ok, %Response{status: 200, body: body}} ->
        with {:ok, release} <- Jason.decode(body) do
          parse_release(release)
        end

      {:ok, %Response{} = response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_release(release) do
    case release do
      %{"tag_name" => "v" <> tag, "prerelease" => prerelease?, "draft" => draft?} ->
        case Version.parse(tag) do
          {:ok, version} ->
            {:ok, %Release{version: to_string(version), prerelease: prerelease? or draft?}}

          :error ->
            {:error, :invalid_release_tag}
        end

      %{} ->
        {:error, :invalid_response}
    end
  end
end
