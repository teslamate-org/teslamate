defmodule TeslaMate.Updater do
  use GenServer
  use Tesla, only: [:get]

  require Logger

  @version Mix.Project.config()[:version]
  @name __MODULE__

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, debug: true, log_level: &log_level/1

  defmodule State, do: defstruct([:update, :version])
  defmodule Release, do: defstruct([:version, :prerelease])

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def get_update(name \\ @name) do
    GenServer.call(name, :get_update, 50)
  catch
    :exit, {:timeout, _} -> nil
    :exit, {:noproc, _} -> nil
  end

  @impl GenServer
  def init(opts) do
    check_after = opts[:check_after] || :timer.minutes(5)
    interval = opts[:interval] || :timer.hours(72)
    version = opts[:version] || @version

    {:ok, _} = :timer.send_interval(interval, :check_for_updates)

    case check_after do
      0 ->
        {:ok, %State{version: version}, {:continue, :check_for_updates}}

      t when is_number(t) and 0 < t ->
        Process.send_after(self(), :check_for_updates, t)
        {:ok, %State{version: version}}
    end
  end

  @impl GenServer
  def handle_continue(:check_for_updates, %State{version: current_vsv} = state) do
    Logger.debug("Checking for updates …")

    case fetch_release() do
      {:ok, %Release{version: version, prerelease: false}} ->
        case Version.compare(current_vsv, version) do
          :lt ->
            Logger.info("Update available: #{current_vsv} -> #{version}")
            {:noreply, %State{state | update: version}}

          _ ->
            Logger.debug("No update available")
            {:noreply, state}
        end

      {:ok, %Release{version: version, prerelease: true}} ->
        Logger.debug("Prerelease available: #{version}")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Update check failed: #{inspect(reason, pretty: true)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:check_for_updates, state) do
    {:noreply, state, {:continue, :check_for_updates}}
  end

  @impl GenServer
  def handle_call(:get_update, _from, %State{update: update} = state) do
    {:reply, update, state}
  end

  ## Private

  defp fetch_release do
    case get("/repos/adriankumpf/teslamate/releases/latest", receive_timeout: 30_000) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        parse_release(body)

      {:ok, %Tesla.Env{} = env} ->
        {:error, reason: "Unexpected response", env: env}

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

  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :warn
  defp log_level(%Tesla.Env{}), do: :debug
end
