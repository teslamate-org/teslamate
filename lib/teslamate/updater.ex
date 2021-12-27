defmodule TeslaMate.Updater do
  use Tesla, only: [:get]

  require Logger

  @version Mix.Project.config()[:version]

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, debug: true, log_level: &log_level/1

  defmodule State, do: defstruct([:update, :version])
  defmodule Release, do: defstruct([:version, :prerelease])

  def init(opts) do
    version = opts[:version] || @version

    {:ok, %State{version: version}}
  end

  def check_for_updates(%State{version: current_vsv} = state) do
    Logger.debug("Checking for updates …")

    case fetch_release() do
      {:ok, %Release{version: version, prerelease: false}} ->
        case Version.compare(current_vsv, version) do
          :lt ->
            Logger.info("Update available: #{current_vsv} -> #{version}")
            %State{state | update: version}

          _ ->
            Logger.debug("No update available")
            state
        end

      {:ok, %Release{version: version, prerelease: true}} ->
        Logger.debug("Prerelease available: #{version}")
        state

      {:error, reason} ->
        Logger.warning("Update check failed: #{inspect(reason, pretty: true)}")
        state
    end
  end

  def get_update(%State{update: update}), do: update

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
